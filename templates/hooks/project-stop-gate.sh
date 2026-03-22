#!/bin/bash
# Hook: Stop (Project)
# Purpose: Block session end unless:
#   1. memr session was closed
#   2. .memorai/ is committed
#   3. If implementer ran, reviewer must also have run

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")

# Check 1: Was session-end called in memr?
DB_PATH="$(pwd)/.memorai/memory.db"
if [ -f "$DB_PATH" ]; then
  SESSION_CLOSED=$(sqlite3 "file://${DB_PATH}?immutable=1" \
    "SELECT COUNT(*) FROM sessions WHERE ended_at IS NOT NULL AND ended_at != '';" 2>/dev/null)
  if [ "$SESSION_CLOSED" = "0" ] || [ -z "$SESSION_CLOSED" ]; then
    echo "SESSION END BLOCKED: No closed session found in memr." >&2
    echo "Run /end to derive beliefs, curate, and close the session." >&2
    echo "Beliefs are the only memory — skipping /end means knowledge is lost." >&2
    exit 2
  fi
fi

# Check 1b: Handoff beliefs exist if session had meaningful work
# Skip in headless mode (heartbeat / non-interactive)
if [ -t 0 ]; then
  CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
  if [ -f "$CTX_FILE" ]; then
    CTX_PCT=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
    CTX_PCT=${CTX_PCT:-0}
    if [ "$CTX_PCT" -gt 10 ] 2>/dev/null; then
      HANDOFF_HITS=$(mem-reason search "handoff" 2>/dev/null | grep -c .)
      if [ "$HANDOFF_HITS" -eq 0 ]; then
        echo "SESSION END BLOCKED: Context is at ${CTX_PCT}% but no handoff beliefs found." >&2
        echo "Create HANDOFF and NEXT beliefs before stopping:" >&2
        echo '  mem-reason add-belief --text "HANDOFF: <what you were working on>" --domain workflow --confidence 0.95 --tags "handoff"' >&2
        echo '  mem-reason add-belief --text "NEXT: <what needs to happen next>" --domain workflow --confidence 0.95 --tags "handoff"' >&2
        exit 2
      fi
    fi
  fi
fi

# Check 2: Is .memorai/ committed?
if [ -d ".memorai" ]; then
  if git diff --name-only .memorai/ 2>/dev/null | grep -q . || \
     git diff --cached --name-only .memorai/ 2>/dev/null | grep -q . || \
     git ls-files --others --exclude-standard .memorai/ 2>/dev/null | grep -q .; then
    echo "SESSION END BLOCKED: .memorai/ has uncommitted changes." >&2
    echo "Commit beliefs: git add .memorai/ && git commit -m 'beliefs: session update'" >&2
    exit 2
  fi
fi

# Check 3: If implementer ran, reviewer must also have run
STATE_FILE="/tmp/${PROJECT_NAME}-agent-state.json"
if [ -f "$STATE_FILE" ]; then
  REVIEW_NEEDED=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
if state.get('implementer_ran') and not state.get('reviewer_ran'):
    print('blocked')
else:
    print('ok')
" 2>/dev/null)

  if [ "$REVIEW_NEEDED" = "blocked" ]; then
    echo "SESSION END BLOCKED: Implementer ran but no reviewer was spawned." >&2
    echo "Code changes require review. Spawn a reviewer agent before ending." >&2
    exit 2
  fi
fi

# Check 4: If project has stakeholders, verify /verify was run
PROJECTS_FILE="$HOME/fang/projects.json"
if [ -f "$PROJECTS_FILE" ]; then
  HAS_WATCHERS=$(python3 -c "
import json, sys
with open('$PROJECTS_FILE') as f:
    data = json.load(f)
for p in data.get('projects', []):
    if p.get('name') == sys.argv[1] and p.get('watchers'):
        print('yes')
        sys.exit(0)
print('no')
" "$PROJECT_NAME" 2>/dev/null)

  if [ "$HAS_WATCHERS" = "yes" ]; then
    STAMP="/tmp/${PROJECT_NAME}-verified"
    if [ ! -f "$STAMP" ]; then
      echo "SESSION END BLOCKED: Project has stakeholders but /verify was not run." >&2
      echo "Run /verify to review stakeholder requirements before ending." >&2
      exit 2
    fi
    # Stamp must be less than 2 hours old
    STAMP_AGE=$(( $(date +%s) - $(date -r "$STAMP" +%s) ))
    if [ "$STAMP_AGE" -gt 7200 ]; then
      echo "SESSION END BLOCKED: /verify stamp is stale (>2h old). Run /verify again." >&2
      exit 2
    fi
  fi
fi

exit 0
