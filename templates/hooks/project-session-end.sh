#!/bin/bash
# project-session-end.sh — Deterministic session-end script for project agents
# Called by /end command. Does: reason, curate, close, commit .memorai/, write report.

set -e
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMR="mem-reason"
PROJECT_NAME=$(basename "$(pwd)")
SUMMARY="${1:-Project session closed via project-session-end.sh}"

echo "=== SESSION END ($PROJECT_NAME) ==="

# Step 1: Derive beliefs from session events
echo ""
echo "--- Step 1: Deriving beliefs ---"
REASON_OUTPUT=$($MEMR reason 2>&1) || true
echo "$REASON_OUTPUT"

# Step 2: Auto-curate stale beliefs
echo ""
echo "--- Step 2: Curating beliefs ---"
CURATED=$($MEMR beliefs --json 2>/dev/null | python3 -c "
import sys, json, subprocess
try:
    beliefs = json.load(sys.stdin)
except:
    print('No beliefs to curate')
    sys.exit(0)

curated = 0
for b in beliefs:
    cc = b.get('contradicting_count', 0)
    conf = b.get('confidence', 1.0)
    bid = b.get('id', '')
    text = b.get('text', '')[:80]

    if cc >= 2 or conf < 0.4:
        subprocess.run(['mem-reason', 'invalidate', bid, '-r',
            f'Session-end curation: contradictions={cc}, confidence={conf}'],
            capture_output=True)
        print(f'CURATED: {text}')
        curated += 1

print(f'Curated {curated} belief(s)')
" 2>/dev/null) || true
echo "$CURATED"

# Step 3: Close the session
echo ""
echo "--- Step 3: Closing session ---"
$MEMR session-end -s "$SUMMARY" 2>&1 || true

# Step 4: Commit .memorai/
echo ""
echo "--- Step 4: Committing beliefs ---"
if [ -d ".memorai" ]; then
    if git diff --name-only .memorai/ 2>/dev/null | grep -q . || \
       git diff --cached --name-only .memorai/ 2>/dev/null | grep -q . || \
       git ls-files --others --exclude-standard .memorai/ 2>/dev/null | grep -q .; then
        git add .memorai/
        git commit -m "beliefs: session update" 2>&1
        echo "Committed .memorai/ changes"
    else
        echo ".memorai/ already clean — no commit needed"
    fi
else
    echo "No .memorai/ directory found"
fi

# Step 5: Write report for coordinator
echo ""
echo "--- Step 5: Writing report ---"
REPORT_DIR="$HOME/fang/reports"
mkdir -p "$REPORT_DIR"
SESSION_NAME="$(tmux display-message -p '#{window_name}' 2>/dev/null || echo "$PROJECT_NAME")"
BELIEF_COUNT=$($MEMR beliefs --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

cat > "$REPORT_DIR/${SESSION_NAME}.json" <<REPORT
{
  "project": "$PROJECT_NAME",
  "session": "$SESSION_NAME",
  "summary": "$SUMMARY",
  "beliefs_active": $BELIEF_COUNT,
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
REPORT
echo "Report written to $REPORT_DIR/${SESSION_NAME}.json"

# Summary
echo ""
echo "=== SESSION END COMPLETE ==="
echo "Active beliefs: $BELIEF_COUNT"
echo "Session closed. Safe to stop."
