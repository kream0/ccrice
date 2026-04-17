#!/bin/bash
# Hook: Stop (Project)
# Purpose: Block session end unless:
#   1. /end was run (report file exists for this session)
#   2. .memorai/ is committed
#   3. If implementer ran, reviewer must also have run
#
# Deadlock protections (added 2026-04-17):
#   - CLASS B: If context-gate is already in "rotate now" state
#     (CTX >= rotate threshold), allow Stop immediately — blocking
#     here creates a mutual deadlock with the context gate.
#   - CLASS D: /verify auto-heal — if the stamp is merely stale,
#     touch it and warn rather than blocking indefinitely.
#   - CLASS E: Consecutive-block cap — after N blocks on the same
#     reason (or any reason within a short window), degrade to allow
#     so the TUI cannot loop "Ran 3 stop hooks" forever.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")

STOP_BLOCK_COUNTER="/tmp/${PROJECT_NAME}-stopgate-blocks"
STOP_BLOCK_REASON_FILE="/tmp/${PROJECT_NAME}-stopgate-reason"
STOP_FIRE_LOG="/tmp/${PROJECT_NAME}-stopgate-fires.log"
MAX_CONSECUTIVE_BLOCKS=3

# Fire-log: record every invocation (bounded to last 50 lines) so soak
# checks can distinguish live fires from stale scrollback replay after
# claude --continue. Best-effort; a write failure must not block exit.
{
  printf '%s pid=%s cwd=%s ctx=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$(pwd)" \
    "$(cat "/tmp/${PROJECT_NAME}-context-pct" 2>/dev/null | tr -d '[:space:]')" \
    >> "$STOP_FIRE_LOG" 2>/dev/null
  if [ -f "$STOP_FIRE_LOG" ]; then
    tail -n 50 "$STOP_FIRE_LOG" > "${STOP_FIRE_LOG}.tmp" 2>/dev/null && \
      mv -f "${STOP_FIRE_LOG}.tmp" "$STOP_FIRE_LOG" 2>/dev/null
  fi
} || true

# ── CLASS B: Context-gate vs stop-gate mutual exclusion ──
# If context is at/above the rotate threshold, the context-gate is
# already blocking every tool the agent would need to satisfy the
# stop-gate's prerequisites. Let the session die cleanly.
CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
CTX_PCT_RAW=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
CTX_PCT=${CTX_PCT_RAW%%.*}
CTX_PCT=${CTX_PCT:-0}
if [ "$CTX_PCT" -ge 50 ] 2>/dev/null; then
  # HARD threshold (200K Opus 4.7, 40/50/60 ladder). At >=50%, the project
  # context-gate is already blocking every tool the agent would need to
  # satisfy the stop-gate's prerequisites. Let the session die cleanly.
  echo "STOP-GATE WARNING: context at ${CTX_PCT}% — allowing exit so a fresh session can take over." >&2
  rm -f "$STOP_BLOCK_COUNTER" "$STOP_BLOCK_REASON_FILE"
  echo '{}'
  exit 0
fi

# Helper: block with consecutive-block cap.
# Arg 1: short reason tag (for dedupe across fires)
# Arg 2+: human-readable message lines printed to stderr
block_or_degrade() {
  local reason_tag="$1"
  shift
  local prev_reason
  prev_reason=$(cat "$STOP_BLOCK_REASON_FILE" 2>/dev/null)
  local blocks
  blocks=$(cat "$STOP_BLOCK_COUNTER" 2>/dev/null || echo 0)
  [[ "$blocks" =~ ^[0-9]+$ ]] || blocks=0

  if [ "$prev_reason" = "$reason_tag" ]; then
    blocks=$(( blocks + 1 ))
  else
    blocks=1
    echo "$reason_tag" > "$STOP_BLOCK_REASON_FILE"
  fi
  echo "$blocks" > "$STOP_BLOCK_COUNTER"

  if [ "$blocks" -ge "$MAX_CONSECUTIVE_BLOCKS" ]; then
    echo "STOP-GATE WARNING: blocked ${blocks}x on '${reason_tag}' — degrading to allow to prevent infinite loop." >&2
    echo "The next session should pick up any unfinished work (see handoff beliefs)." >&2
    rm -f "$STOP_BLOCK_COUNTER" "$STOP_BLOCK_REASON_FILE"
    echo '{}'
    exit 0
  fi

  # Emit the caller's message lines to stderr; build reason string for JSON
  local reason_parts=()
  local line
  for line in "$@"; do
    echo "$line" >&2
    reason_parts+=("$line")
  done
  echo "(consecutive block ${blocks}/${MAX_CONSECUTIVE_BLOCKS} on '${reason_tag}' — further blocks will degrade to allow)" >&2
  local reason_str
  reason_str=$(IFS=' '; echo "${reason_parts[*]}")
  python3 -c "import json,sys; print(json.dumps({'decision':'block','reason':sys.argv[1]}))" "$reason_str"
  exit 0
}

# Check 1: Was /end run? (writes report file + handoff belief)
REPORT_DIR="$HOME/fang/reports"
SESSION_NAME="${FANG_WINDOW_NAME:-proj-${PROJECT_NAME}}"
REPORT_FILE="$REPORT_DIR/${SESSION_NAME}.json"
if [ ! -f "$REPORT_FILE" ]; then
  block_or_degrade "no-report" \
    "SESSION END BLOCKED: No session report found." \
    "Run /end to curate beliefs, create handoff, and write report." \
    "Beliefs are the only memory — skipping /end means knowledge is lost."
fi

# Verify report is from this session (less than 2 hours old)
if [ -f "$REPORT_FILE" ]; then
  REPORT_AGE=$(( $(date +%s) - $(date -r "$REPORT_FILE" +%s 2>/dev/null || echo 0) ))
  if [ "$REPORT_AGE" -gt 7200 ]; then
    block_or_degrade "stale-report" \
      "SESSION END BLOCKED: Session report is stale (${REPORT_AGE}s old)." \
      "Run /end again to create a fresh handoff and report."
  fi
fi

# Check 1b: Handoff beliefs exist if session had meaningful work
# Skip in headless mode (heartbeat / non-interactive)
if [ -t 0 ]; then
  if [ -f "$CTX_FILE" ]; then
    CTX_CHECK=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
    CTX_CHECK=${CTX_CHECK%%.*}
    CTX_CHECK=${CTX_CHECK:-0}
    if [ "$CTX_CHECK" -gt 10 ] 2>/dev/null; then
      HANDOFF_HITS=$(mem-reason beliefs -d handoff 2>/dev/null | grep -c .)
      if [ "$HANDOFF_HITS" -eq 0 ]; then
        block_or_degrade "no-handoff" \
          "SESSION END BLOCKED: Context is at ${CTX_CHECK}% but no handoff beliefs found." \
          "Create a handoff before stopping:" \
          '  mem-reason handoff "STATE: <what you were working on>. NEXT: <what needs to happen>."'
      fi
    fi
  fi
fi

# Check 2: Is .memorai/ committed?
if [ -d ".memorai" ]; then
  if git diff --name-only .memorai/ 2>/dev/null | grep -q . || \
     git diff --cached --name-only .memorai/ 2>/dev/null | grep -q . || \
     git ls-files --others --exclude-standard .memorai/ 2>/dev/null | grep -q .; then
    block_or_degrade "memorai-dirty" \
      "SESSION END BLOCKED: .memorai/ has uncommitted changes." \
      "Commit beliefs: git add .memorai/ && git commit -m 'beliefs: session update'"
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
    block_or_degrade "no-reviewer" \
      "SESSION END BLOCKED: Implementer ran but no reviewer was spawned." \
      "Code changes require review. Spawn a reviewer agent before ending."
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
      block_or_degrade "no-verify" \
        "SESSION END BLOCKED: Project has stakeholders but /verify was not run." \
        "Run /verify to review stakeholder requirements before ending."
    fi
    # CLASS D: /verify auto-heal — stale stamp is refreshed, not blocked.
    # Blocking on staleness creates a loop where hook fires "run /verify"
    # but the agent has no tool calls between fires (it's a stop hook).
    STAMP_AGE=$(( $(date +%s) - $(date -r "$STAMP" +%s) ))
    if [ "$STAMP_AGE" -gt 7200 ]; then
      echo "STOP-GATE WARNING: /verify stamp is stale (${STAMP_AGE}s old). Auto-refreshing." >&2
      echo "The next interactive session should run /verify to refresh stakeholder review." >&2
      touch "$STAMP"
    fi
  fi
fi

# All gates passed — clear block counter
rm -f "$STOP_BLOCK_COUNTER" "$STOP_BLOCK_REASON_FILE"
echo '{}'
exit 0
