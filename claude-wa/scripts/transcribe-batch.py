#!/usr/bin/env python3
"""Batch transcription: loads model once, transcribes many files.
Input (stdin): JSON object {"id1": "/path/to/file1", "id2": "/path/to/file2", ...}
Output (stdout): JSON object {"id1": "transcription text", "id2": "transcription text", ...}
"""
import json, sys, subprocess, tempfile, os

# Auto-detect cuDNN before importing faster_whisper
try:
    import nvidia.cudnn
    cudnn_lib = os.path.dirname(nvidia.cudnn.__file__) + "/lib"
    if os.path.isdir(cudnn_lib):
        os.environ["LD_LIBRARY_PATH"] = cudnn_lib + ":" + os.environ.get("LD_LIBRARY_PATH", "")
except Exception:
    pass

file_map = json.load(sys.stdin)
if not file_map:
    print("{}")
    sys.exit(0)

# Convert all files to WAV first (fast, parallel-friendly)
wav_map = {}
for msg_id, path in file_map.items():
    wav = tempfile.mktemp(suffix=".wav", prefix=f"wa_{msg_id}_")
    ret = subprocess.run(
        ["ffmpeg", "-i", path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav, "-y", "-loglevel", "error"],
        capture_output=True,
    )
    if ret.returncode == 0:
        wav_map[msg_id] = wav
    else:
        print(f"ffmpeg error for {msg_id}: {ret.stderr.decode()}", file=sys.stderr)

# Auto-detect GPU: try cuda first, fall back to cpu
from faster_whisper import WhisperModel

model_name = os.environ.get("WA_WHISPER_MODEL", "large-v3")
lang = os.environ.get("WA_WHISPER_LANG", "fr")

try:
    model = WhisperModel(model_name, device="cuda", compute_type="int8")
except Exception as e:
    print(f"CUDA unavailable ({e}), falling back to CPU", file=sys.stderr)
    model = WhisperModel(model_name, device="cpu", compute_type="int8")

transcribe_kwargs = {"language": lang} if lang else {}

results = {}
for msg_id, wav_path in wav_map.items():
    try:
        segments, _ = model.transcribe(wav_path, **transcribe_kwargs)
        results[msg_id] = " ".join(s.text.strip() for s in segments)
    except Exception as e:
        results[msg_id] = f"[transcription error: {e}]"
        print(f"transcribe error for {msg_id}: {e}", file=sys.stderr)
    finally:
        os.unlink(wav_path)

print(json.dumps(results, ensure_ascii=False))
