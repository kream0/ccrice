#!/bin/bash
# Hook: PostToolUse[Agent] (Project)
# Purpose: Validate agent output has structured report format.
# Non-blocking (PostToolUse), but warns if output is unstructured.
# Also marks review-needed if implementer ran.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")
INPUT=$(cat)

AGENT_OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.text // .tool_result // ""' 2>/dev/null | head -c 2000)
STATE_FILE="/tmp/${PROJECT_NAME}-agent-state.json"

# Check for structured report markers
HAS_STRUCTURE=false
if echo "$AGENT_OUTPUT" | grep -qE "(TASK COMPLETE|REVIEW COMPLETE|TEST COMPLETE|Status:|Issues found:|Tests run:)"; then
  HAS_STRUCTURE=true
fi

if [ "$HAS_STRUCTURE" = "false" ]; then
  echo "WARNING: Agent output missing structured report format." >&2
  echo "Expected one of: TASK COMPLETE, REVIEW COMPLETE, TEST COMPLETE" >&2
  echo "With fields: Status, Files modified, Changes, Validation" >&2
fi

# If an implementer just finished, flag that review is needed
if [ -f "$STATE_FILE" ]; then
  IMPL_RAN=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
if state.get('implementer_ran') and not state.get('reviewer_ran'):
    print('true')
else:
    print('false')
" 2>/dev/null)

  if [ "$IMPL_RAN" = "true" ]; then
    echo "REMINDER: Implementer completed work. Spawn a reviewer agent before ending the session." >&2
  fi
fi

# --- Chrome orphan cleanup ---
# After Agent tool completes, kill orphaned Chrome processes from agent-browser sessions.
# Orphan = user-data-dir matches /tmp/agent-browser-chrome-* AND either:
#   - ppid=1 (reparented after sub-agent died), or
#   - remote-debugging-port has 0 established TCP connections

orphan_pids=()
orphan_dirs=()

while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  [ -d "/proc/$pid" ] || continue

  cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null) || continue
  user_data_dir=$(echo "$cmdline" | grep -oP '(?<=--user-data-dir=)/tmp/agent-browser-chrome-\S+')
  [ -n "$user_data_dir" ] || continue

  ppid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null) || continue
  is_orphan=false

  # Signal 1: reparented to init (parent died)
  [ "$ppid" = "1" ] && is_orphan=true

  # Signal 2: debugging port with no established connections
  if [ "$is_orphan" = "false" ]; then
    debug_port=$(echo "$cmdline" | grep -oP '(?<=--remote-debugging-port=)\d+')
    if [ -n "$debug_port" ]; then
      established=$(ss -tnp state established "sport = :$debug_port" 2>/dev/null | tail -n +2 | wc -l)
      [ "$established" -eq 0 ] && is_orphan=true
    fi
  fi

  if [ "$is_orphan" = "true" ]; then
    echo "Killing orphaned Chrome PID $pid (ppid=$ppid, dir=$user_data_dir)" >&2
    kill "$pid" 2>/dev/null
    orphan_pids+=("$pid")
    # Track unique dirs
    local_found=false
    for d in "${orphan_dirs[@]}"; do [ "$d" = "$user_data_dir" ] && local_found=true; done
    [ "$local_found" = "false" ] && orphan_dirs+=("$user_data_dir")
  fi
done < <(pgrep -f 'chrome.*user-data-dir=/tmp/agent-browser-chrome' 2>/dev/null)

if [ ${#orphan_pids[@]} -gt 0 ]; then
  sleep 1
  # Force-kill any that didn't exit gracefully
  for pid in "${orphan_pids[@]}"; do
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  done
  # Remove temp profile dirs
  for dir in "${orphan_dirs[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir" 2>/dev/null && echo "Removed $dir" >&2
  done
  echo "Chrome orphan cleanup: killed ${#orphan_pids[@]} stale process(es)" >&2
fi

exit 0
