#!/bin/bash

# Ralph Wiggum Pre-Compact Hook (Memorai Edition)
# Preserves session ID for context restoration after /compact
# Session memory persists in memorai - no need to copy data

set -euo pipefail

RALPH_STATE_FILE=".claude/ralph-loop.local.md"
COMPACT_PRESERVE_FILE=".claude/RALPH_COMPACT_PRESERVE.md"

# Only act if ralph-loop is active
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Parse session_id from state file (handles CRLF line endings)
parse_frontmatter() {
  sed 's/\r$//' "$1" | sed -n '/^---$/,/^---$/{ /^---$/d; p; }'
}

get_yaml_value() {
  echo "$1" | tr -d '\r' | grep "^$2:" | sed "s/$2: *//" | sed 's/^"\(.*\)"$/\1/'
}

get_yaml_nested_value() {
  echo "$1" | tr -d '\r' | grep "^  $2:" | sed "s/  $2: *//" | sed 's/^"\(.*\)"$/\1/'
}

FRONTMATTER=$(parse_frontmatter "$RALPH_STATE_FILE")
SESSION_ID=$(get_yaml_value "$FRONTMATTER" "session_id")
ITERATION=$(get_yaml_value "$FRONTMATTER" "iteration")
COMPLETION_PROMISE=$(get_yaml_value "$FRONTMATTER" "completion_promise")
CURRENT_STRATEGY=$(get_yaml_nested_value "$FRONTMATTER" "current")
STUCK_COUNT=$(get_yaml_nested_value "$FRONTMATTER" "stuck_count")

# Create preserve file with full state for recovery
{
  echo "# Ralph Context (Preserved for Compaction)"
  echo ""
  echo "_This file was auto-generated before /compact to preserve session reference._"
  echo ""
  echo "**Session ID:** $SESSION_ID"
  echo "**Iteration:** $ITERATION"
  echo "**Strategy:** ${CURRENT_STRATEGY:-explore}"
  echo "**Stuck Count:** ${STUCK_COUNT:-0}"
  if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
    echo "**Completion Promise:** $COMPLETION_PROMISE"
  fi
  echo ""
  echo "Session memory is stored in Memorai and will be restored automatically."
  echo ""
  echo "---"
  echo "_After compact, context will be restored from memorai._"
} > "$COMPACT_PRESERVE_FILE"

echo "📋 Ralph: Preserved session ID for compaction (memorai data persists)"

exit 0
