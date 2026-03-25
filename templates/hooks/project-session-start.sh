#!/bin/bash
# Hook: SessionStart (Project)
# Purpose: Initialize memr session, auto-curate stale beliefs, load project + global context.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMR="mem-reason"
PROJECT_NAME=$(basename "$(pwd)")

# Reset context cache so statusline shows 0% immediately after /clear
echo "0" > "/tmp/${PROJECT_NAME}-context-pct" 2>/dev/null || true

# Initialize memr if first session ever
if [ ! -d ".memorai" ]; then
  $MEMR init 2>/dev/null
fi

# Start a new session
$MEMR session-start 2>/dev/null

# Auto-curate: invalidate heavily contradicted or low-confidence beliefs
$MEMR beliefs --json 2>/dev/null | python3 -c "
import sys, json, subprocess
try:
    beliefs = json.load(sys.stdin)
except:
    sys.exit(0)

curated = 0
for b in beliefs:
    bid = b.get('id', '')
    text = b.get('text', '')[:80]
    cc = b.get('contradicting_count', 0)
    conf = b.get('confidence', 1.0)

    if cc >= 3:
        subprocess.run(['mem-reason', 'invalidate', bid, '-r',
            f'Auto-invalidated: {cc} contradictions exceeded threshold'],
            capture_output=True)
        print(f'CURATED: invalidated (contradicted {cc}x): {text}')
        curated += 1
    elif conf < 0.3:
        subprocess.run(['mem-reason', 'invalidate', bid, '-r',
            f'Auto-invalidated: confidence {conf} below threshold 0.3'],
            capture_output=True)
        print(f'CURATED: invalidated (confidence {conf}): {text}')
        curated += 1

if curated > 0:
    print(f'Auto-curated {curated} belief(s)')
" 2>/dev/null

# Load handoff beliefs first — these are the most important after /clear
echo "=== HANDOFF FROM PREVIOUS SESSION ==="
$MEMR search "handoff" 2>/dev/null || echo "(no handoff beliefs found)"
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
(cd "$HOME/fang" && $MEMR search "handoff" 2>/dev/null) || true
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
