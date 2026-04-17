#!/bin/bash
# Hook: PreToolUse (project agent context gate)
# Blocks non-essential tool calls when context exceeds 50% (~100K tokens).
# Standard 200K Opus 4.7 window (never the 1M variant). Gate calibrated to
# the 40/50/60 soft/hard/emergency ladder from fang-heartbeat.sh.
# Allows: mem-reason, git, fang-msg, Skill (/end, /clear, /start), Read
# Goal: force the agent to wrap up instead of doing more work.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Always allow wrap-up tools — agent needs these to rotate
case "$TOOL" in
  Skill|Read|Glob|Grep) exit 0 ;;
esac

# Always allow wrap-up commands
if echo "$CMD" | grep -qE "^(mem-reason |git |fang-msg |~/fang/display/fang-msg )"; then
  exit 0
fi

# Read context % from statusline cache (written by project-context-statusline.sh)
PROJECT_NAME=$(basename "$(pwd)")
CTX_PCT=$(cat "/tmp/${PROJECT_NAME}-context-pct" 2>/dev/null)
[ -z "$CTX_PCT" ] && exit 0
# Truncate to integer
CTX_PCT=${CTX_PCT%%.*}

if [ "$CTX_PCT" -ge 50 ]; then
  PROJECT_NAME=$(basename "$(pwd)")
  echo "TOOL BLOCKED — CONTEXT ROTATION REQUIRED" >&2
  echo "Context at ${CTX_PCT}% of 200K. HARD limit reached (>=50%)." >&2
  echo "" >&2
  echo "Execute wrap-up sequence NOW:" >&2
  echo "  1. mem-reason add-belief --text 'HANDOFF: <current task>' --domain workflow --confidence 0.95 --tags handoff" >&2
  echo "  2. mem-reason add-belief --text 'NEXT: <what comes next>' --domain workflow --confidence 0.95 --tags handoff" >&2
  echo "  3. git add -A && git commit -m 'wip: context rotation'" >&2
  echo "  4. ~/fang/display/fang-msg ${PROJECT_NAME} Status 'Context rotation at ${CTX_PCT}%. Wrapping up and clearing.'" >&2
  echo "  5. /end" >&2
  echo "  6. /clear" >&2
  echo "" >&2
  echo "Only mem-reason, git, fang-msg, and /end|/clear are allowed." >&2
  exit 2
fi

exit 0
