#!/bin/bash

# Ralph Wiggum Session Resume Hook (Memorai Edition)
# Reinjects context when a session resumes (e.g., after /compact or reconnect)
# Queries memorai for session state

set -euo pipefail

# Check for required dependency (bun is optional - script falls back gracefully)
if ! command -v bun &>/dev/null; then
  # Bun not available, continue without memorai integration
  :
fi

RALPH_STATE_FILE=".claude/ralph-loop.local.md"
COMPACT_PRESERVE_FILE=".claude/RALPH_COMPACT_PRESERVE.md"

# Get plugin root directory for TypeScript access
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Only act if ralph-loop is active
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Parse state file (handles CRLF line endings)
parse_frontmatter() {
  sed 's/\r$//' "$1" | sed -n '/^---$/,/^---$/{ /^---$/d; p; }'
}

get_yaml_value() {
  echo "$1" | tr -d '\r' | grep "^$2:" | sed "s/$2: *//" | sed 's/^"\(.*\)"$/\1/'
}

FRONTMATTER=$(parse_frontmatter "$RALPH_STATE_FILE")
ITERATION=$(get_yaml_value "$FRONTMATTER" "iteration")
SESSION_ID=$(get_yaml_value "$FRONTMATTER" "session_id")
COMPLETION_PROMISE=$(get_yaml_value "$FRONTMATTER" "completion_promise")

# Query memorai for session context using inline bun script
# Pass SESSION_ID via environment variable to avoid injection vulnerabilities
MEMORAI_CONTEXT=$(SESSION_ID="$SESSION_ID" bun -e "
import { MemoraiClient, databaseExists } from 'memorai';

if (!databaseExists()) {
  console.log('');
  process.exit(0);
}

let client;
try {
  client = new MemoraiClient();
} catch (e) {
  console.log('');
  process.exit(0);
}

const sessionId = process.env.SESSION_ID || '';
if (!sessionId) {
  console.log('');
  process.exit(0);
}

// Query objective
const objResults = client.search({
  query: sessionId,
  tags: ['ralph', 'ralph-session-objective'],
  limit: 1,
});

let objective = '';
if (objResults.length > 0) {
  const mem = client.get(objResults[0].id, { full: true });
  if (mem && 'content' in mem) {
    objective = mem.content;
  }
}

// Query state
const stateResults = client.search({
  query: sessionId,
  tags: ['ralph', 'ralph-session-state'],
  limit: 1,
});

let status = '';
let nextActions = [];
if (stateResults.length > 0) {
  const mem = client.get(stateResults[0].id, { full: true });
  if (mem && 'content' in mem) {
    try {
      const state = JSON.parse(mem.content);
      status = state.current_status || '';
      nextActions = state.next_actions || [];
    } catch {}
  }
}

// Query learnings
const learningResults = client.search({
  query: sessionId,
  tags: ['ralph', 'learning'],
  limit: 5,
});
const learnings = learningResults
  .filter(r => r.title.startsWith('Ralph Learning:'))
  .map(r => r.title.replace('Ralph Learning: ', '').trim());

// Output formatted context
const lines = [];
lines.push('## Original Objective');
lines.push(objective || '_Not found_');
lines.push('');
lines.push('## Current Status');
lines.push(status || '_Not found_');
lines.push('');
if (nextActions.length > 0) {
  lines.push('## Next Actions');
  nextActions.forEach((a, i) => lines.push((i + 1) + '. ' + a));
  lines.push('');
}
if (learnings.length > 0) {
  lines.push('## Key Learnings');
  learnings.forEach(l => lines.push('- ' + l));
  lines.push('');
}

console.log(lines.join('\\n'));
" 2>/dev/null || echo "")

# Build context injection message
{
  echo "# Ralph Session Context"
  echo ""
  echo "**You are in an active Ralph loop at iteration $ITERATION.**"
  echo "**Session ID:** $SESSION_ID"
  echo ""

  # Track if we successfully restored context (for cleanup decision)
  CONTEXT_RESTORED=false

  if [[ -n "$MEMORAI_CONTEXT" ]]; then
    echo "_Context restored from Memorai:_"
    echo ""
    echo "$MEMORAI_CONTEXT"
    CONTEXT_RESTORED=true
  else
    # Fallback to preserve file if memorai query failed
    if [[ -f "$COMPACT_PRESERVE_FILE" ]]; then
      echo "_Context reference from pre-compact preservation:_"
      echo ""
      cat "$COMPACT_PRESERVE_FILE"
      CONTEXT_RESTORED=true
    else
      echo "_Note: Session data stored in Memorai. Query may have failed._"
    fi
  fi

  echo ""
  echo "---"
  if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
    echo "Continue working on the task. When complete, output: \`<promise>$COMPLETION_PROMISE</promise>\`"
  else
    echo "Continue working on the task."
  fi
}

# Only clean up compact preserve file after successful context restoration
# This prevents data loss if both memorai and preserve file fail
if [[ "$CONTEXT_RESTORED" == "true" ]] && [[ -f "$COMPACT_PRESERVE_FILE" ]]; then
  rm "$COMPACT_PRESERVE_FILE"
fi

exit 0
