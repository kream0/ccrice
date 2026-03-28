#!/bin/bash
# Hook: SessionStart (Project)
# Purpose: Run memr curate + orient, load project + global context.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMR="mem-reason"
PROJECT_NAME=$(basename "$(pwd)")

# Reset context cache so statusline shows 0% immediately after /clear
echo "0" > "/tmp/${PROJECT_NAME}-context-pct" 2>/dev/null || true

# Reset idle-guard state for fresh session
rm -f "/tmp/${PROJECT_NAME}-idle-blocks" 2>/dev/null || true

# Initialize memr if first session ever
if [ ! -d ".memorai" ]; then
  $MEMR init 2>/dev/null
fi

# Auto-curate stale beliefs (v2 native — replaces Python curation block)
$MEMR curate 2>/dev/null

# Orient: structured session-start context
echo "=== SESSION ORIENTATION ==="
$MEMR orient 2>/dev/null
echo ""

# Load handoff beliefs first — these are the most important after /clear
echo "=== HANDOFF FROM PREVIOUS SESSION ==="
$MEMR beliefs -d handoff 2>/dev/null || echo "(no handoff beliefs found)"
echo ""

# Load project-specific beliefs
echo "=== PROJECT BELIEFS ($PROJECT_NAME) ==="
$MEMR context 2>/dev/null
echo ""

# Load relevant global beliefs from coordinator's store
echo "=== GLOBAL BELIEFS (relevant to $PROJECT_NAME) ==="
(cd "$HOME/fang" && $MEMR search "$PROJECT_NAME" 2>/dev/null) || true
(cd "$HOME/fang" && $MEMR search "deploy" 2>/dev/null) || true
(cd "$HOME/fang" && $MEMR search "stakeholder" 2>/dev/null) || true
(cd "$HOME/fang" && $MEMR beliefs -d handoff 2>/dev/null) || true
echo ""

echo "=== SESSION RULES ==="
echo "1. DELEGATE all source changes to agents — hook will block direct edits"
echo "2. VERIFY before claiming done — test with curl or agent-browser"
echo "3. Run /end before stopping — beliefs are the only memory"
echo "4. Commit .memorai/ after belief changes"

# Write beliefs + rules to fallback file
FALLBACK="/tmp/${PROJECT_NAME}-session-beliefs.txt"
{
  echo "=== PROJECT BELIEFS ($PROJECT_NAME) ==="
  $MEMR context 2>/dev/null
  echo ""
  echo "=== SESSION RULES ==="
  echo "1. DELEGATE all source changes to agents — hook will block direct edits"
  echo "2. VERIFY before claiming done — test with curl or agent-browser"
  echo "3. Run /end before stopping — beliefs are the only memory"
  echo "4. Commit .memorai/ after belief changes"
} > "$FALLBACK"

exit 0
