#!/bin/bash
# Hook: Stop (Project)
# Purpose: Block session end unless:
#   0. The roadmap is complete (no .roadmap-active sentinel) — AUTONOMOUS gate.
#      This runs FIRST and closes the /end-report escape hatch: running /end
#      writes a report file (Check 1) but does NOT prove the product is done.
#      While the sentinel exists the agent must keep looping.
#   1. /end was run (report file exists for this session)
#   2. .memorai/ is committed
#   3. If implementer ran, reviewer must also have run
#
# Deadlock-safety: EVERY blocking path in this gate is bounded by a shared
# 5-consecutive-blocks circuit breaker (block_or_degrade). After 5 blocks on the
# same reason the gate DEGRADES to allow + emits an alert, so the Stop chain can
# never wedge a session forever. This mirrors the idle-guard breaker that runs
# immediately before this hook, keeping the two coordinated (a roadmap-active
# stop is first caught by idle-guard's breaker, then by this one).

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")

# Per-project context mode (autonomous | classic). Materialized by fang-spawn from
# projects.json into .claude/.context-mode (the same sentinel the idle-guard reads).
# An "autonomous" resident (always_on, e.g. hotseat) runs a self-driving feature
# loop and NEVER runs /end — so the /end artifacts (report file + handoff beliefs)
# are never produced and their staleness checks (Check 1 / Check 1b) would
# false-block EVERY quiet turn-end forever (#124: the report went 14.7h stale and
# the bare `exit 2` re-fired on each Stop). Those two checks are /end-ritual gates,
# skipped in autonomous mode below. Check 2 (.memorai committed), Check 3
# (reviewer-after-implementer) and Check 4 (stakeholder /verify) are real work
# invariants — they still apply in every mode.
CONTEXT_MODE=$(cat ".claude/.context-mode" 2>/dev/null | tr -d '[:space:]')

# ── Shared circuit breaker (deadlock safety) ──────────────────────────────
# Counts consecutive blocks per reason-tag in /tmp and degrades to ALLOW after
# MAX_CONSECUTIVE_BLOCKS so no blocking path can loop the TUI forever.
STOP_BLOCK_COUNTER="/tmp/${PROJECT_NAME}-stopgate-blocks"
STOP_BLOCK_REASON_FILE="/tmp/${PROJECT_NAME}-stopgate-reason"
MAX_CONSECUTIVE_BLOCKS=5

# Rate-limit yield: if the fleet is paused for an API rate limit, never block a
# stop (blocking would force the agent to keep calling the model and burn quota).
# Signal source = the heartbeat's own flags in $FANG_DIR/.heartbeat-state/
# (`rate-limited-<target>` or the legacy `rate-limited`); /tmp + env flags are
# escape hatches. Yielding here is deadlock-safe by construction.
RL_STATE_DIR="${FANG_DIR:-$HOME/fang}/.heartbeat-state"
if ls "$RL_STATE_DIR"/rate-limited* >/dev/null 2>&1 || \
   [ -f "/tmp/${PROJECT_NAME}-rate-limited" ] || [ -f "/tmp/fang-rate-limited" ] || \
   [ "${FANG_RATE_LIMITED:-}" = "1" ]; then
  echo "STOP-GATE: rate-limited — allowing stop to avoid quota burn." >&2
  rm -f "$STOP_BLOCK_COUNTER" "$STOP_BLOCK_REASON_FILE"
  exit 0
fi

# block_or_degrade <reason-tag> <message-line...>
# Blocks (exit 2) until the same reason has fired MAX_CONSECUTIVE_BLOCKS times,
# then degrades to allow (exit 0) with a loud alert.
block_or_degrade() {
  local reason_tag="$1"; shift
  local prev_reason blocks
  prev_reason=$(cat "$STOP_BLOCK_REASON_FILE" 2>/dev/null)
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
    echo "STOP-GATE WARNING: blocked ${blocks}x on '${reason_tag}' — degrading to allow to prevent an infinite loop." >&2
    echo "The next session must pick up unfinished work (see handoff beliefs)." >&2
    # Best-effort observability: tell the coordinator a breaker tripped.
    "$HOME/fang/display/fang-msg" "$PROJECT_NAME" Alert \
      "stop-gate breaker tripped: ${reason_tag} degraded to allow after ${blocks} blocks" \
      >/dev/null 2>&1 || true
    rm -f "$STOP_BLOCK_COUNTER" "$STOP_BLOCK_REASON_FILE"
    exit 0
  fi

  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "(consecutive block ${blocks}/${MAX_CONSECUTIVE_BLOCKS} on '${reason_tag}' — further blocks degrade to allow)" >&2
  exit 2
}

# ── Check 0: Roadmap complete? — DE-DUPED, now owned solely by the idle-guard ──
# The `.roadmap-active` / `.roadmap-gated` decision is made ONCE, by
# project-idle-guard.sh, which runs immediately BEFORE this hook in the Stop
# chain. Claude Code runs every Stop hook in the array regardless of an earlier
# hook's exit code, so when this gate ALSO blocked on the bare sentinel the
# owner saw a DOUBLED "DON'T STOP / SESSION END BLOCKED roadmap-active"
# injection on every turn-end (and it false-fired on a delegating agent that had
# merely yielded its turn to a running sub-agent). The idle-guard is the more
# complete owner of this decision — it is now progress/delegation-aware (allows
# the quiet turn-end on a recent commit/edit/spawn or an in_progress task) and
# carries its own 5-consecutive-block breaker. So the roadmap-active block lives
# there and ONLY there; this hook no longer emits a second copy.
#
# Coordination preserved: a genuine roadmap-active stall is still blocked by the
# idle-guard (exit 2) BEFORE control reaches here, and bounded by the idle-guard
# breaker. This gate keeps its OWN shared breaker (block_or_degrade) for its
# other reasons (report-file / .memorai / reviewer / verify), so removing this
# branch cannot deadlock — the remaining breaker paths are unchanged.

# Checks 1 + 1b below are /end-ritual artifacts (a fresh report file + handoff
# beliefs). They are SKIPPED in autonomous mode (#124): an always_on resident
# never runs /end, so the report goes perpetually stale and the bare `exit 2`
# false-blocks every quiet turn-end. Classic (/end-driven) sessions keep both.
if [ "$CONTEXT_MODE" != "autonomous" ]; then

# Check 1: Was /end run? (writes report file + handoff belief)
REPORT_DIR="$HOME/fang/reports"
SESSION_NAME="${FANG_WINDOW_NAME:-proj-${PROJECT_NAME}}"
REPORT_FILE="$REPORT_DIR/${SESSION_NAME}.json"
if [ ! -f "$REPORT_FILE" ]; then
  echo "SESSION END BLOCKED: No session report found." >&2
  echo "Run /end to curate beliefs, create handoff, and write report." >&2
  echo "Beliefs are the only memory — skipping /end means knowledge is lost." >&2
  exit 2
fi

# Verify report is from this session (less than 2 hours old)
if [ -f "$REPORT_FILE" ]; then
  REPORT_AGE=$(( $(date +%s) - $(date -r "$REPORT_FILE" +%s 2>/dev/null || echo 0) ))
  if [ "$REPORT_AGE" -gt 7200 ]; then
    echo "SESSION END BLOCKED: Session report is stale (${REPORT_AGE}s old)." >&2
    echo "Run /end again to create a fresh handoff and report." >&2
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
      HANDOFF_HITS=$(mem-reason beliefs -d handoff 2>/dev/null | grep -c .)
      if [ "$HANDOFF_HITS" -eq 0 ]; then
        echo "SESSION END BLOCKED: Context is at ${CTX_PCT}% but no handoff beliefs found." >&2
        echo "Create a handoff before stopping:" >&2
        echo '  mem-reason handoff "STATE: <what you were working on>. NEXT: <what needs to happen>."' >&2
        exit 2
      fi
    fi
  fi
fi
fi  # end: skip /end-ritual checks (Check 1 + 1b) in autonomous mode (#124)

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
  REVIEW_NEEDED=$(jq -r 'if .implementer_ran and (.reviewer_ran | not) then "blocked" else "ok" end' "$STATE_FILE" 2>/dev/null)

  if [ "$REVIEW_NEEDED" = "blocked" ]; then
    echo "SESSION END BLOCKED: Implementer ran but no reviewer was spawned." >&2
    echo "Code changes require review. Spawn a reviewer agent before ending." >&2
    exit 2
  fi
fi

# Check 4: If project has stakeholders, verify /verify was run
PROJECTS_FILE="$HOME/fang/projects.json"
if [ -f "$PROJECTS_FILE" ]; then
  HAS_WATCHERS=$(jq -r --arg name "$PROJECT_NAME" 'if any(.projects[]; .name == $name and (.watchers | length > 0)) then "yes" else "no" end' "$PROJECTS_FILE" 2>/dev/null)

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
