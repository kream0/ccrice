"""Shared transcription helpers for wa transcribe.

Provides:
- detect_media_kind(path) -> "audio" | "video"
- transcribe_audio(model, wav_path, lang=None) -> str
- transcribe_video(model, src_path, work_dir, lang=None) -> str
  Returns an interleaved transcript with timestamped segments and
  perceptually-deduplicated frame markers.

Format (video):
    [00:00.0 --> 00:08.4] Par rapport au calcul de commission, ...
    [frame @ 00:00] /tmp/wa-frames-<id>/frame_0001.jpg
    [frame @ 00:08] /tmp/wa-frames-<id>/frame_0005.jpg
    [00:08.4 --> 00:21.0] ...

Format (audio): raw concatenated text (legacy unchanged).
"""

import json
import math
import os
import re
import subprocess
import tempfile
from glob import glob


# ---------- media detection ----------

def detect_media_kind(path):
    """Return 'video' if the file has a video stream, else 'audio'."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type",
             "-of", "json", path],
            capture_output=True, text=True, timeout=15, check=False,
        )
        data = json.loads(out.stdout or "{}")
        for s in data.get("streams", []):
            if s.get("codec_type") == "video":
                return "video"
    except Exception:
        pass
    return "audio"


def _probe_duration(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nokey=1:noprint_wrappers=1", path],
            capture_output=True, text=True, timeout=15, check=False,
        )
        return float((out.stdout or "0").strip() or 0.0)
    except Exception:
        return 0.0


# ---------- ffmpeg helpers ----------

def extract_wav(src, dst_wav):
    """Extract mono 16k WAV from any audio/video. Raises on failure."""
    subprocess.run(
        ["ffmpeg", "-i", src, "-ar", "16000", "-ac", "1",
         "-c:a", "pcm_s16le", dst_wav, "-y", "-loglevel", "error"],
        check=True, capture_output=True, timeout=180,
    )


def extract_frames(src, out_dir, fps=0.5):
    """Extract frames at given fps. Returns sorted list of frame paths."""
    os.makedirs(out_dir, exist_ok=True)
    # Wipe previous frames in this dir so retries are clean
    for old in glob(os.path.join(out_dir, "frame_*.jpg")):
        try:
            os.unlink(old)
        except OSError:
            pass
    subprocess.run(
        ["ffmpeg", "-i", src, "-vf", "fps=%s" % fps, "-q:v", "3",
         os.path.join(out_dir, "frame_%04d.jpg"),
         "-y", "-loglevel", "error"],
        check=True, capture_output=True, timeout=240,
    )
    return sorted(glob(os.path.join(out_dir, "frame_*.jpg")))


# ---------- frame selection ----------

def _phash_hamming_dedup(frames, threshold=8):
    """Keep first frame, drop subsequent frames whose pHash distance from the
    last KEPT frame is < threshold. Return list of (index, path) tuples where
    index is 1-based position in original frame stream."""
    import imagehash
    from PIL import Image

    kept = []
    last_hash = None
    for i, fp in enumerate(frames, start=1):
        try:
            with Image.open(fp) as im:
                h = imagehash.phash(im)
        except Exception:
            continue
        if last_hash is None or (h - last_hash) >= threshold:
            kept.append((i, fp))
            last_hash = h
    return kept


def _cap_evenly(kept, cap):
    """If kept exceeds cap, drop frames evenly. Always preserves first frame."""
    n = len(kept)
    if cap <= 0 or n <= cap:
        return kept
    if cap == 1:
        return [kept[0]]
    # Pick `cap` indices evenly spaced across [0, n-1]
    step = (n - 1) / (cap - 1)
    picked_idxs = sorted({round(step * k) for k in range(cap)})
    # In rare cases rounding gives fewer than cap unique indices — pad
    if len(picked_idxs) < cap:
        for k in range(n):
            if k not in picked_idxs:
                picked_idxs.append(k)
                if len(picked_idxs) >= cap:
                    break
        picked_idxs = sorted(set(picked_idxs))
    return [kept[i] for i in picked_idxs[:cap]]


# ---------- transcript formatting ----------

def _fmt_ts(seconds, with_decimal=False):
    seconds = max(0.0, float(seconds))
    m = int(seconds // 60)
    s = seconds - m * 60
    if with_decimal:
        return "%02d:%04.1f" % (m, s)
    return "%02d:%02d" % (m, int(s))


def _frame_index_to_seconds(idx, fps):
    """ffmpeg numbers frames starting at 1; frame N corresponds to time (N-1)/fps."""
    return max(0.0, (idx - 1) / fps)


def _interleave(segments, frames, fps):
    """segments: list of (start, end, text). frames: list of (orig_idx, path).
    Place each frame after the segment whose start <= frame_time.
    If no segment starts before the frame, the frame goes before all segments."""
    seg_buckets = [[] for _ in range(len(segments) + 1)]
    for orig_idx, path in frames:
        t = _frame_index_to_seconds(orig_idx, fps)
        slot = 0  # 0 = "before any segment"
        for j, (st, _en, _tx) in enumerate(segments):
            if st <= t:
                slot = j + 1
            else:
                break
        seg_buckets[slot].append((t, path))

    out_lines = []
    for t, p in seg_buckets[0]:
        out_lines.append("[frame @ %s] %s" % (_fmt_ts(t), p))
    for j, (st, en, tx) in enumerate(segments):
        out_lines.append("[%s --> %s] %s" % (_fmt_ts(st, True), _fmt_ts(en, True), tx.strip()))
        for t, p in seg_buckets[j + 1]:
            out_lines.append("[frame @ %s] %s" % (_fmt_ts(t), p))
    return "\n".join(out_lines)


# ---------- main entry points ----------

def transcribe_audio(model, wav_path, lang=None):
    """Plain audio transcript — concatenated segments, legacy behavior."""
    kwargs = {"language": lang} if lang else {}
    segments, _ = model.transcribe(wav_path, **kwargs)
    return " ".join(s.text.strip() for s in segments)


def transcribe_video(model, src_path, work_dir, lang=None, fps=0.5,
                     hamming_threshold=8, frames_per_minute=20):
    """Full video pipeline: audio + framed visual context.

    work_dir: directory for extracted frames (created if missing).
    Returns the formatted interleaved string with a one-line header.
    """
    os.makedirs(work_dir, exist_ok=True)

    duration = _probe_duration(src_path)

    wav_path = os.path.join(work_dir, "audio.wav")
    extract_wav(src_path, wav_path)

    kwargs = {"language": lang} if lang else {}
    segments_iter, _ = model.transcribe(wav_path, **kwargs)
    segments = [(float(s.start or 0), float(s.end or 0), s.text or "")
                for s in segments_iter]

    try:
        os.unlink(wav_path)
    except OSError:
        pass

    frames = extract_frames(src_path, work_dir, fps=fps)
    kept = _phash_hamming_dedup(frames, threshold=hamming_threshold)

    cap_total = max(1, math.ceil((duration / 60.0) * frames_per_minute)) if duration > 0 else len(kept)
    capped = _cap_evenly(kept, cap_total)

    kept_paths = set(p for _, p in capped)
    for fp in frames:
        if fp not in kept_paths:
            try:
                os.unlink(fp)
            except OSError:
                pass

    if not segments and not capped:
        return "(no audio segments detected; no frames retained)"
    body = _interleave(segments, capped, fps)
    header = ("# %d frame(s) kept of %d extracted "
              "(fps=%s, hamming>=%d, cap=%d, duration=%.1fs)"
              % (len(capped), len(frames), fps, hamming_threshold, cap_total, duration))
    return header + "\n" + body


def make_work_dir(msg_id):
    """Create the per-message frames dir under /tmp."""
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", msg_id or "anon")
    p = os.path.join(tempfile.gettempdir(), "wa-frames-%s" % safe)
    os.makedirs(p, exist_ok=True)
    return p
