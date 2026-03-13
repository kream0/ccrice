#!/usr/bin/env bash
# Usage: transcribe.sh <audio_or_video_file>
# Converts any audio/video to 16kHz WAV, runs faster-whisper, prints text
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

TMP=$(mktemp /tmp/wa_XXXX.wav)
trap 'rm -f "$TMP"' EXIT

ffmpeg -i "$1" -ar 16000 -ac 1 -c:a pcm_s16le "$TMP" -y -loglevel error

python3 -c "
import torch
from faster_whisper import WhisperModel
device = 'cuda' if torch.cuda.is_available() else 'cpu'
compute = 'int8' if device == 'cuda' else 'int8'
m = WhisperModel('large-v3', device=device, compute_type=compute)
segs, _ = m.transcribe('$TMP', language='fr')
print(' '.join(s.text.strip() for s in segs))
"
