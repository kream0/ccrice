#!/bin/bash
# Hook: PostToolUse[Bash] (Project)
# Purpose: Clean up orphaned Chrome processes after agent-browser close/quit
# or after agent-browser errors. Runs fang-chrome-cleanup for full wipe,
# or targeted orphan kill for session-specific cleanup.

INPUT=$(cat)

# Only trigger on Bash tool calls
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // 0' 2>/dev/null)

# Check if this is an agent-browser command
echo "$COMMAND" | grep -q 'agent-browser' || exit 0

CLEANUP_REASON=""

# Trigger 1: explicit close/quit
if echo "$COMMAND" | grep -qE 'agent-browser\s+(close|quit|exit)'; then
  CLEANUP_REASON="close"
fi

# Trigger 2: agent-browser error (non-zero exit)
if [ "${EXIT_CODE:-0}" != "0" ] && [ -z "$CLEANUP_REASON" ]; then
  CLEANUP_REASON="error (exit=$EXIT_CODE)"
fi

[ -n "$CLEANUP_REASON" ] || exit 0

# Extract --session name if present
SESSION=$(echo "$COMMAND" | grep -oP '(?<=--session\s)\S+' || true)

if [ -n "$SESSION" ]; then
  # Targeted cleanup: only kill Chrome for this session
  KILLED=0
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null) || continue
    if echo "$cmdline" | grep -q "agent-browser-chrome-$SESSION"; then
      echo "Killing Chrome for session '$SESSION' PID $pid (reason: $CLEANUP_REASON)" >&2
      kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
    fi
  done < <(pgrep -f 'chrome.*user-data-dir=/tmp/agent-browser-chrome' 2>/dev/null || true)
  # Clean session temp dir
  if [ -d "/tmp/agent-browser-chrome-$SESSION" ]; then
    rm -rf "/tmp/agent-browser-chrome-$SESSION" 2>/dev/null
    echo "Removed /tmp/agent-browser-chrome-$SESSION" >&2
  fi
  [ "$KILLED" -gt 0 ] && echo "Session cleanup ($CLEANUP_REASON): killed $KILLED Chrome process(es)" >&2
else
  # No session specified — clean up orphans (ppid=1 or no debug connections)
  KILLED=0
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    [ -d "/proc/$pid" ] || continue
    ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || continue
    is_orphan=false
    [ "$ppid" = "1" ] && is_orphan=true
    if [ "$is_orphan" = "false" ]; then
      cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null) || continue
      debug_port=$(echo "$cmdline" | grep -oP '(?<=--remote-debugging-port=)\d+')
      if [ -n "$debug_port" ]; then
        established=$(ss -tnp state established "sport = :$debug_port" 2>/dev/null | tail -n +2 | wc -l)
        [ "$established" -eq 0 ] && is_orphan=true
      fi
    fi
    if [ "$is_orphan" = "true" ]; then
      echo "Killing orphaned Chrome PID $pid (reason: $CLEANUP_REASON)" >&2
      kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
    fi
  done < <(pgrep -f 'chrome.*user-data-dir=/tmp/agent-browser-chrome' 2>/dev/null || true)
  [ "$KILLED" -gt 0 ] && echo "Orphan cleanup ($CLEANUP_REASON): killed $KILLED Chrome process(es)" >&2
fi

exit 0
