#!/usr/bin/env bash
# Idempotent setup: installs node deps, checks and installs prerequisites.
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

# Check and install system prerequisites
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[claude-wa] ffmpeg not found. Attempting install..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y ffmpeg 2>/dev/null || echo "[claude-wa] WARNING: could not install ffmpeg (try: sudo apt-get install ffmpeg)"
  elif command -v brew >/dev/null 2>&1; then
    brew install ffmpeg 2>/dev/null || echo "[claude-wa] WARNING: could not install ffmpeg (try: brew install ffmpeg)"
  else
    echo "[claude-wa] WARNING: ffmpeg not found. Install it manually for transcription support."
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[claude-wa] WARNING: python3 not found. Install Python 3 for transcription support."
fi

# Install faster-whisper + torch if missing
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c "import faster_whisper" 2>/dev/null; then
    echo "[claude-wa] Installing faster-whisper and torch (this may take a minute)..."
    python3 -m pip install --quiet faster-whisper torch 2>/dev/null || \
      echo "[claude-wa] WARNING: could not install faster-whisper (try: pip install faster-whisper torch)"
  fi
fi

# First-run check: remind about WhatsApp connection
if [[ ! -d "$DIR/.data/auth" ]]; then
  echo "[claude-wa] First run detected — WhatsApp not yet connected."
  echo "[claude-wa] Run: /whatsapp start and scan the QR code to connect."
fi
