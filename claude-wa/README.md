# claude-wa

WhatsApp bridge plugin for Claude Code.

## Prerequisites

- Node.js >= 18
- Python 3
- ffmpeg
- faster-whisper (`pip install faster-whisper`)
- Optional: NVIDIA GPU + cuDNN for fast transcription (falls back to CPU automatically)

## Install

```
/plugin marketplace add owner/ccrice
/plugin install claude-wa@ccrice
```

> Adjust `owner` to match your marketplace username.

## First run

1. Start the service: `wa start`
2. Scan the QR code: `wa log`
3. Check connection: `wa status`

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
