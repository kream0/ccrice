#!/bin/bash
# project-session-end.sh — Deterministic session-end script for project agents
# Called by /end command. Does: curate, handoff, commit .memorai/, write report.

set -e
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMR="mem-reason"
PROJECT_NAME=$(basename "$(pwd)")
SUMMARY="${1:-Project session closed via project-session-end.sh}"

echo "=== SESSION END ($PROJECT_NAME) ==="

# Step 1: Auto-curate stale beliefs (v2 native)
echo ""
echo "--- Step 1: Curating beliefs ---"
CURATE_OUTPUT=$($MEMR curate 2>&1) || true
echo "$CURATE_OUTPUT"

# Step 2: Create handoff belief (auto-supersedes previous handoffs)
echo ""
echo "--- Step 2: Creating handoff ---"
$MEMR handoff "$SUMMARY" 2>&1 || true

# Step 3: Commit .memorai/
echo ""
echo "--- Step 3: Committing beliefs ---"
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

# Step 4: Write report for coordinator
echo ""
echo "--- Step 4: Writing report ---"
REPORT_DIR="$HOME/fang/reports"
mkdir -p "$REPORT_DIR"
SESSION_NAME="${FANG_WINDOW_NAME:-proj-${PROJECT_NAME}}"
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
