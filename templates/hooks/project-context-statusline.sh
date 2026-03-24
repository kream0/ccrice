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

# Output statusline text
if [ -n "$PCT" ]; then
  if [ "$PCT" -ge 23 ]; then
    echo "${PROJECT} CTX:${PCT}% ROTATE NOW"
  elif [ "$PCT" -ge 20 ]; then
    echo "${PROJECT} CTX:${PCT}% wrap up"
  else
    echo "${PROJECT} CTX:${PCT}%"
  fi
fi
