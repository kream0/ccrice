#!/usr/bin/env python3
"""Batch transcription: loads model once, transcribes many files.

Input (stdin): JSON object {"id1": "/path/to/file1", "id2": "/path/to/file2", ...}
Output (stdout): JSON object {"id1": "transcription text", "id2": "transcription text", ...}

For video inputs, the output text is the same interleaved format as
`wa transcribe` (segment timestamps + frame markers).
"""
import json, sys, os, hashlib, tempfile

# Auto-detect cuDNN before importing faster_whisper
try:
    import nvidia.cudnn
    cudnn_lib = os.path.dirname(nvidia.cudnn.__file__) + "/lib"
    if os.path.isdir(cudnn_lib):
        os.environ["LD_LIBRARY_PATH"] = cudnn_lib + ":" + os.environ.get("LD_LIBRARY_PATH", "")
except Exception:
    pass

# Make the shared helper importable (script lives next to it)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import transcribe_lib as tlib  # noqa: E402

file_map = json.load(sys.stdin)
if not file_map:
    print("{}")
    sys.exit(0)

# Load whisper once (CUDA → CPU fallback)
from faster_whisper import WhisperModel

model_name = os.environ.get("WA_WHISPER_MODEL", "small")
lang = os.environ.get("WA_WHISPER_LANG", "fr")

try:
    model = WhisperModel(model_name, device="cuda", compute_type="int8")
except Exception as e:
    print(f"CUDA unavailable ({e}), falling back to CPU", file=sys.stderr)
    model = WhisperModel(model_name, device="cpu", compute_type="int8")

transcribe_kwargs = {"language": lang} if lang else {}

results = {}
for msg_id, path in file_map.items():
    try:
        kind = tlib.detect_media_kind(path)
        if kind == "video":
            work = tlib.make_work_dir(msg_id)
            results[msg_id] = tlib.transcribe_video(
                model, path, work, lang=lang or None,
            )
        else:
            wav = tempfile.mktemp(suffix=".wav", prefix=f"wa_{msg_id}_")
            try:
                tlib.extract_wav(path, wav)
                results[msg_id] = tlib.transcribe_audio(model, wav, lang=lang or None)
            finally:
                try: os.unlink(wav)
                except OSError: pass
    except Exception as e:
        results[msg_id] = f"[transcription error: {e}]"
        print(f"transcribe error for {msg_id}: {e}", file=sys.stderr)

print(json.dumps(results, ensure_ascii=False))
