#!/bin/bash
# Hook: PreToolUse[Bash] — Agent-browser lifecycle management
# PERMANENT FIX: Ensures clean Chrome state BEFORE every agent-browser call.
# Kills stale daemons + orphaned Chrome from previous sessions so the new
# command always gets a fresh browser.
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
echo "$COMMAND" | grep -q 'agent-browser' || exit 0

# Only do full cleanup before open/navigate/goto which launch a new browser
if echo "$COMMAND" | grep -qE 'agent-browser\s+(open|goto|navigate|connect)\b'; then
  STALE_COUNT=0

  # Kill orphaned daemons (parent=1 means their session is gone)
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || continue
    if [ "$ppid" = "1" ]; then
      kill "$pid" 2>/dev/null && STALE_COUNT=$((STALE_COUNT + 1))
    fi
  done < <(pgrep -f 'agent-browser-linux-x64' 2>/dev/null || true)

  # Kill zombie Chrome by killing their parents
  while IFS= read -r zpid; do
    [ -z "$zpid" ] && continue
    ppid=$(awk '{print $4}' /proc/$zpid/stat 2>/dev/null) || continue
    [ "$ppid" != "1" ] && kill "$ppid" 2>/dev/null || true
  done < <(ps -eo pid,stat,comm 2>/dev/null | awk '$2 ~ /Z/ && $3 ~ /chrome/ {print $1}')

  # Kill orphaned Chrome trees (main process whose daemon is dead)
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null) || continue
    echo "$cmdline" | grep -q '\-\-remote-debugging-port' || continue
    ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || continue
    if [ "$ppid" = "1" ] || ! kill -0 "$ppid" 2>/dev/null; then
      kill "$pid" 2>/dev/null && STALE_COUNT=$((STALE_COUNT + 1))
    fi
  done < <(pgrep -f 'chrome.*user-data-dir=/tmp/agent-browser-chrome' 2>/dev/null || true)

  # Clean stale temp dirs (no Chrome process references them)
  for dir in /tmp/agent-browser-chrome-*; do
    [ -d "$dir" ] || continue
    pgrep -f "user-data-dir=$dir" >/dev/null 2>&1 || rm -rf "$dir" 2>/dev/null
  done

  [ "$STALE_COUNT" -gt 0 ] && echo "Pre-launch cleanup: killed $STALE_COUNT stale process(es)" >&2
fi

exit 0
