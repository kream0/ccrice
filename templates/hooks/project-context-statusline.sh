#!/bin/bash
# Statusline script for project agents
# Receives context_window JSON on stdin, caches used_percentage to file.
# The PreToolUse hook (project-context-gate.sh) reads this file.

INPUT=$(cat)
PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
PROJECT=$(basename "$(echo "$INPUT" | jq -r '.workspace.current_dir // empty' 2>/dev/null)" 2>/dev/null)
[ -z "$PROJECT" ] && PROJECT=$(basename "$(pwd)")
RATE_DIR="$HOME/fang/.heartbeat-state"

if [ -n "$PCT" ]; then
  echo "$PCT" > "/tmp/${PROJECT}-context-pct"
fi

# Extract rate limit data (shared across all sessions — write to central location)
FIVE_PCT=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
SEVEN_PCT=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
FIVE_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
SEVEN_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

if [ -n "$FIVE_PCT" ]; then
  echo "$FIVE_PCT" > "$RATE_DIR/rate-5h-pct"
  [ -n "$FIVE_RESET" ] && echo "$FIVE_RESET" > "$RATE_DIR/rate-5h-reset"
fi
if [ -n "$SEVEN_PCT" ]; then
  echo "$SEVEN_PCT" > "$RATE_DIR/rate-7d-pct"
  [ -n "$SEVEN_RESET" ] && echo "$SEVEN_RESET" > "$RATE_DIR/rate-7d-reset"
fi

# Build statusline text
RATE_TAG=""
if [ -n "$FIVE_PCT" ]; then
  FIVE_INT=${FIVE_PCT%.*}
  if [ "${FIVE_INT:-0}" -ge 90 ]; then
    RATE_TAG=" 5h:${FIVE_INT}% CRITICAL"
  elif [ "${FIVE_INT:-0}" -ge 75 ]; then
    RATE_TAG=" 5h:${FIVE_INT}% HIGH"
  elif [ "${FIVE_INT:-0}" -ge 50 ]; then
    RATE_TAG=" 5h:${FIVE_INT}%"
  fi
fi

if [ -n "$PCT" ]; then
  if [ "$PCT" -ge 50 ]; then
    echo "${PROJECT} CTX:${PCT}% ROTATE NOW${RATE_TAG}"
  elif [ "$PCT" -ge 40 ]; then
    echo "${PROJECT} CTX:${PCT}% wrap up${RATE_TAG}"
  else
    echo "${PROJECT} CTX:${PCT}%${RATE_TAG}"
  fi
fi
