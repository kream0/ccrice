#!/usr/bin/env bash
# Idempotent setup: installs node deps, checks prerequisites.
# Called on SessionStart via hook and before wa start.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# Install node dependencies if missing
if [[ ! -d "$DIR/node_modules" ]]; then
  echo "[claude-wa] Installing node dependencies..."
  (cd "$DIR" && npm install --production --no-fund --no-audit 2>&1) || {
    echo "[claude-wa] ERROR: npm install failed. Ensure Node.js >= 18 is installed."
    exit 1
  }
fi

# Check prerequisites (non-fatal warnings)
MISSING=""
command -v ffmpeg  >/dev/null 2>&1 || MISSING+=" ffmpeg"
command -v python3 >/dev/null 2>&1 || MISSING+=" python3"

if [[ -n "$MISSING" ]]; then
  echo "[claude-wa] WARNING: missing optional deps:$MISSING (needed for transcription)"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -c "import faster_whisper" 2>/dev/null || \
    echo "[claude-wa] WARNING: faster-whisper not installed (pip install faster-whisper). Transcription won't work."
fi
