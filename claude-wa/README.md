# claude-wa

WhatsApp bridge plugin for Claude Code.

## Prerequisites

- Node.js >= 18
- Python 3 (for transcription)
- ffmpeg (for transcription)

The plugin auto-installs Node dependencies and `faster-whisper` + `torch` on first run. System packages (`ffmpeg`, `python3`) are attempted via apt/brew if missing.

For video transcription, the `imagehash` and `Pillow` Python packages are also required:
```bash
python3 -m pip install --user imagehash Pillow
# or, on Debian/Ubuntu PEP 668 systems:
python3 -m pip install --user --break-system-packages imagehash Pillow
```

## Install

```
/install https://github.com/kream0/ccrice/tree/main/claude-wa
```

On first session start, the plugin will:
1. Install Node.js dependencies
2. Install `faster-whisper` and `torch` via pip (if not already present)
3. Prompt you to connect WhatsApp by scanning a QR code

## First run

1. Type `/whatsapp status` — Claude will detect the service isn't running, start it, and show you the QR code to scan.
2. Open WhatsApp on your phone > Settings > Linked Devices > Link a Device, and scan the QR code.
3. Once connected, you're good to go.

## Configuration

Set these environment variables to customize transcription:

| Variable | Default | Description |
|----------|---------|-------------|
| `WA_PORT` | `7777` | HTTP API port |
| `WA_WHISPER_MODEL` | `medium` | Whisper model (`tiny`, `base`, `small`, `medium`, `large-v3`) |
| `WA_WHISPER_LANG` | `fr` | Transcription language (ISO code, or empty for auto-detect) |

Example (in your shell profile or `.env`):
```bash
export WA_WHISPER_MODEL=medium
export WA_WHISPER_LANG=en
```

## Commands

| Command | Description |
|---------|-------------|
| `wa start` | Start WhatsApp service (background) |
| `wa stop` | Stop WhatsApp service |
| `wa log` | Tail service log (QR code appears here) |
| `wa status` | Connection status |
| `wa chats` | List recent chats |
| `wa messages [opts]` | Fetch messages (`--chat`, `--since`, `--limit`, `--search`) |
| `wa send <chat> <text>` | Send a message |
| `wa media <id>` | Download media file |
| `wa transcribe <id>` | Transcribe voice/audio/video |
| `wa export [opts]` | Export conversation (`--chat`, `--exclude`, `--include`, `--transcribe`, `--since`) |

## Video transcription

`wa transcribe <id>` automatically detects video messages and runs an enriched pipeline:

1. Extract audio → whisper transcribe with per-segment start/end timestamps.
2. Sample frames at fps=0.5 (one frame every 2 s).
3. Deduplicate with perceptual hash (Hamming distance ≥ 8 from last kept frame).
4. Cap retained frames at 20 per minute of video; if dedup leaves more, drop evenly.
5. Interleave frames with transcript segments by timestamp.

Output (video):
```
Transcription (video):
# 21 frame(s) kept of 86 extracted (fps=0.5, hamming>=8, cap=58, duration=171.1s)
[00:00.0 --> 00:18.0] Par rapport au calcul de commission ...
[frame @ 00:00] /tmp/wa-frames-<id>/frame_0001.jpg
[frame @ 00:02] /tmp/wa-frames-<id>/frame_0002.jpg
[00:18.0 --> 00:39.0] Le calcul de commission du 29 mars ...
[frame @ 00:24] /tmp/wa-frames-<id>/frame_0013.jpg
...
```

Audio-only messages keep the legacy format (`Transcription (voice):\n<text>`). Retained frames stay on disk under `/tmp/wa-frames-<id>/` so the agent can open them; dropped frames are unlinked immediately.

The same pipeline runs when `wa export --transcribe` processes video messages, since both paths share `transcribe_lib.py`.
