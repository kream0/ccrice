# claude-wa

WhatsApp bridge plugin for Claude Code.

## Prerequisites

- Node.js >= 18
- Python 3 (for transcription)
- ffmpeg (for transcription)

The plugin auto-installs Node dependencies and `faster-whisper` + `torch` on first run. System packages (`ffmpeg`, `python3`) are attempted via apt/brew if missing.

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
