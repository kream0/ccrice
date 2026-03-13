---
description: Monitor, search, and interact with WhatsApp conversations. Usage: /whatsapp <action> [args]
---

You have access to WhatsApp via the `${CLAUDE_PLUGIN_ROOT}/scripts/wa` CLI. It returns human-readable formatted text.

## Commands

- `${CLAUDE_PLUGIN_ROOT}/scripts/wa status` — connection status
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa chats` — list recent chats (resolves group names automatically)
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa messages --chat X --since 10m --limit 50 --search keyword` — fetch messages (all flags optional)
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa send <chat_jid> <message text>` — send a message
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa media <message_id>` — download media file, prints path
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa describe <message_id>` — download image (alias for media), then use Read tool to view it
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa transcribe <message_id>` — transcribe a single voice/audio/video to text
- `${CLAUDE_PLUGIN_ROOT}/scripts/wa export --chat <name> [--exclude image,video] [--include voice,text] [--transcribe] [--since 7d]` — export full conversation as compact log, with optional batch transcription

## Instructions

The user said: $ARGUMENTS

Based on their request:

1. First run `${CLAUDE_PLUGIN_ROOT}/scripts/wa status` to confirm the service is connected.
2. Interpret the user's intent and call the appropriate commands.
3. Output is already formatted — present it directly, add summary or highlights if useful.
4. If the user asks to "monitor" a chat, fetch recent messages and summarize what's happening.
5. If the user asks to "react" or "respond", draft a message and **always confirm with the user before sending**.
6. For project monitoring, look for keywords like deadlines, blockers, decisions, action items, deployments.

## Export workflow (preferred for bulk analysis)

When the user asks to extract knowledge, summarize, or analyze a full conversation, use `wa export`:

```bash
# Full conversation, transcribe voice messages, skip images/videos
wa export --chat "Project Name" --exclude image,video --transcribe

# Only voice messages, transcribed
wa export --chat "Project Name" --include voice --transcribe

# Recent text messages only
wa export --chat "Project Name" --include text --since 7d
```

The export command does ALL heavy lifting server-side:
- Filters messages by type (include whitelist or exclude blacklist)
- Batch-transcribes all voice/audio/video in one shot (model loaded once)
- Returns a compact conversation log ready for analysis

This is the most token-efficient way to consume a conversation — use it for any bulk task.

## Single-message media workflows

For individual messages (not bulk):
- **Voice/audio**: `wa transcribe <id>`
- **Images**: `wa media <id>` then use Read tool on the returned path
- **Videos**: `wa transcribe <id>` for audio content, `wa media <id>` for the file
- **Documents**: `wa media <id>` then Read the file

## Chat identification

- `--chat` accepts partial matches: use a name fragment, phone number, or group JID.
- `wa chats` resolves group names automatically — use it to find the right JID.

## Important
- NEVER call `wa send` without explicit user confirmation.
- Export with `--transcribe` can take a few minutes for many voice messages (model loading + processing).
- Media files and transcriptions are cached — repeat calls are instant.
