#!/bin/bash
# Statusline script for project agents
# Receives context_window JSON on stdin, caches used_percentage to file.
# The PreToolUse hook (project-context-gate.sh) reads this file.

INPUT=$(cat)
PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
PROJECT=$(basename "$(echo "$INPUT" | jq -r '.workspace.current_dir // empty' 2>/dev/null)" 2>/dev/null)
[ -z "$PROJECT" ] && PROJECT=$(basename "$(pwd)")

if [ -n "$PCT" ]; then
  echo "$PCT" > "/tmp/${PROJECT}-context-pct"
fi

# Output statusline text — thresholds match 40/50/60 ladder (200K Opus 4.7)
if [ -n "$PCT" ]; then
  if [ "$PCT" -ge 50 ]; then
    echo "${PROJECT} CTX:${PCT}% ROTATE NOW"
  elif [ "$PCT" -ge 40 ]; then
    echo "${PROJECT} CTX:${PCT}% wrap up"
  else
    echo "${PROJECT} CTX:${PCT}%"
  fi
fi
