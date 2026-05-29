#!/usr/bin/env bash
# Usage: transcribe.sh <audio_or_video_file>
# For audio: runs faster-whisper, prints text.
# For video: extracts audio + deduplicated frames with timestamps, prints
# an interleaved transcript with [frame @ MM:SS] markers.
set -euo pipefail

# Auto-detect cuDNN libs for GPU-accelerated whisper
CUDNN_LIB=$(python3 -c "
try:
    import nvidia.cudnn, os
    print(os.path.dirname(nvidia.cudnn.__file__) + '/lib')
except Exception:
    pass
" 2>/dev/null || true)

if [[ -n "$CUDNN_LIB" && -d "$CUDNN_LIB" ]]; then
  export LD_LIBRARY_PATH="$CUDNN_LIB:${LD_LIBRARY_PATH:-}"
fi

if [[ -z "${1:-}" ]]; then
  echo "Usage: transcribe.sh <file>" >&2
  exit 1
fi

SRC="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PYTHONPATH="$SCRIPT_DIR:${PYTHONPATH:-}"

python3 - "$SRC" <<'PYEOF'
import os, sys, tempfile, hashlib
sys.path.insert(0, os.environ.get("PYTHONPATH", "").split(":", 1)[0])
import transcribe_lib as tlib
from faster_whisper import WhisperModel

src = sys.argv[1]
model_name = os.environ.get("WA_WHISPER_MODEL", "medium")
lang = os.environ.get("WA_WHISPER_LANG", "")

import torch
device = "cuda" if torch.cuda.is_available() else "cpu"
model = WhisperModel(model_name, device=device, compute_type="int8")

kind = tlib.detect_media_kind(src)
if kind == "video":
    # Stable per-source work dir under /tmp
    base = os.path.basename(src)
    key = os.path.splitext(base)[0] or hashlib.sha1(src.encode()).hexdigest()[:12]
    work = tlib.make_work_dir(key)
    out = tlib.transcribe_video(model, src, work, lang=lang or None)
    print(out)
else:
    wav = tempfile.mktemp(suffix=".wav", prefix="wa_")
    try:
        tlib.extract_wav(src, wav)
        print(tlib.transcribe_audio(model, wav, lang=lang or None))
    finally:
        try: os.unlink(wav)
        except OSError: pass
PYEOF
