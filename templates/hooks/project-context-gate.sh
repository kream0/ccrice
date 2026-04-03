#!/bin/bash
# Hook: PreToolUse (project agent context gate)
# Blocks non-essential tool calls when context exceeds 50% context.
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
  echo "Context at ${CTX_PCT}% (~${CTX_PCT}0K tokens). Hard limit reached." >&2
  echo "" >&2
  echo "Execute wrap-up sequence NOW:" >&2
  echo "  1. mem-reason handoff 'STATE: <current task>. NEXT: <what comes next>. BLOCKERS: <any>.'" >&2
  echo "  2. git add -A && git commit -m 'wip: context rotation'" >&2
  echo "  3. ~/fang/display/fang-msg ${PROJECT_NAME} Status 'Context rotation at ${CTX_PCT}%. Wrapping up and clearing.'" >&2
  echo "  4. /end" >&2
  echo "  5. /clear" >&2
  echo "" >&2
  echo "Only mem-reason, git, fang-msg, and /end|/clear are allowed." >&2
  exit 2
fi

exit 0
