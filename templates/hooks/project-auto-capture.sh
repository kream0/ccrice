#!/bin/bash
# Hook: PostToolUse on Edit|Write|Bash (Project)
# Purpose: Auto-capture significant tool calls as memr events.
# Non-blocking (PostToolUse cannot block). Runs in background.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Edit|Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // "unknown"' 2>/dev/null)
    mem-reason capture -t file_change --file "$FILE" 2>/dev/null &
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | head -c 200)
    # Only capture significant commands
    if echo "$CMD" | grep -qE "deploy|test|npm (run|test|install)|git (push|commit)|migrat|fang-publish"; then
      mem-reason capture -t tool_call --tool "Bash" --message "$CMD" 2>/dev/null &
    fi
    ;;
esac

exit 0
