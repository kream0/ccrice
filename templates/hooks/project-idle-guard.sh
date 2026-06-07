#!/bin/bash
# Hook: Stop — Idle Guard (deterministic pre-checks)
# Purpose: Prevent agents from going idle with unfinished work.
# Runs BEFORE the prompt-type LLM evaluation and the session-hygiene stop-gate.
# Checks: uncommitted code changes, unchecked TODO items, AND (autonomous mode)
#         an incomplete roadmap — see "Roadmap-incomplete checks" below.
# Circuit breakers: 5 consecutive blocks (deadlock safety), no assigned inbox
# task (standby mode). Context-threshold rotation is DISABLED — native
# auto-compact owns context (see #65); see Circuit breaker 1 below.

# Stop hooks receive a JSON payload on stdin ({session_id, transcript_path,
# stop_hook_active, ...}). Capture it non-destructively so we can map this
# session to its Claude Code task store. NEVER block on a parse failure — an
# unreadable payload must degrade to "no tasks found" (deadlock-safe).
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT=$(cat 2>/dev/null)
fi

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")
SESSION_NAME="${FANG_WINDOW_NAME:-proj-${PROJECT_NAME}}"

# ── Circuit breaker 0: Rate-limit yield ──
# The idle-guard runs FIRST in the Stop chain, so it must yield under a rate
# limit too — otherwise it blocks the stop and forces the agent to keep calling
# the model, burning quota that is already exhausted. Yielding here is
# deadlock-safe by construction (it only ever allows). Mirrors the stop-gate.
# Signal source = the heartbeat's own flags in $FANG_DIR/.heartbeat-state/:
# a per-target `rate-limited-<target>` file (or the legacy `rate-limited`) is
# present while the fleet is paused. The fang-rate-limited / FANG_RATE_LIMITED
# escape hatches let an operator or test force the yield.
RL_STATE_DIR="${FANG_DIR:-$HOME/fang}/.heartbeat-state"
if ls "$RL_STATE_DIR"/rate-limited* >/dev/null 2>&1 || \
   [ -f "/tmp/${PROJECT_NAME}-rate-limited" ] || [ -f "/tmp/fang-rate-limited" ] || \
   [ "${FANG_RATE_LIMITED:-}" = "1" ]; then
  echo "IDLE GUARD: rate-limited — allowing stop to avoid quota burn." >&2
  rm -f "/tmp/${PROJECT_NAME}-idle-blocks"
  exit 0
fi

# ── Circuit breaker 1: Context rotation — DISABLED (#65 2026-06-06) ──
# The whole fleet runs on Claude Code's native auto-compact; agents are told
# NOT to monitor context % (fang-spawn prompt). Letting a context threshold
# trigger `exit 0` here made autonomous agents (e.g. hotseat) STOP mid-loop at
# ~40–50% with the project still incomplete — exactly the bug native
# auto-compact was supposed to retire. We no longer allow a stop on context %.
# Deadlock-safety is preserved by Circuit breaker 2 (5 consecutive blocks).
# Kept reversible per the #65 neutering pattern (cf. project-context-gate.sh).
#
# CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
# CTX_PCT=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
# CTX_PCT=${CTX_PCT:-0}
# CTX_PCT=${CTX_PCT%%.*}
# if [ "${CTX_PCT:-0}" -ge 40 ] 2>/dev/null; then
#   rm -f "/tmp/${PROJECT_NAME}-idle-blocks"
#   exit 0
# fi

# ── Circuit breaker 2: Max consecutive blocks ──
# After 5 consecutive blocks the guard DEGRADES to allow so it can never loop
# the TUI forever. Semantics: the counter is incremented on each blocked fire
# (in the Verdict block below), so by the time the guard fires for the 5th time
# the stored count is already 4 — the prospective 5th block would reach 5, which
# trips the breaker and ALLOWS instead. This matches the stop-gate breaker
# (allow on the 5th consecutive fire), keeping the two coordinated (see
# feedback_hook_deadlocks). MAX_IDLE_BLOCKS is the trip threshold.
MAX_IDLE_BLOCKS=5
BLOCK_FILE="/tmp/${PROJECT_NAME}-idle-blocks"
BLOCKS=$(cat "$BLOCK_FILE" 2>/dev/null || echo 0)
[[ "$BLOCKS" =~ ^[0-9]+$ ]] || BLOCKS=0
if [ "$(( BLOCKS + 1 ))" -ge "$MAX_IDLE_BLOCKS" ] 2>/dev/null; then
  echo "WARNING: Idle guard would block for the ${MAX_IDLE_BLOCKS}th consecutive time. Allowing stop to prevent an infinite loop." >&2
  echo "The next session must pick up unfinished work (see handoff beliefs)." >&2
  rm -f "$BLOCK_FILE"
  exit 0
fi

# ── Circuit breaker 3: Standby mode (CLASS C fix) ──
# A resident agent with no assigned inbox task, no uncommitted code,
# and no unchecked TODO items is not going idle with unfinished work —
# it is correctly on standby. The LLM-judge variant in settings.json was
# flagging these as "going idle without a clear reason" and blocking forever.
#
# We consider the agent "on standby" if ALL of these hold:
#   - No inbox messages addressed to this session (~/fang/inbox/*${SESSION_NAME}*.msg
#     or ~/fang/inbox/*${PROJECT_NAME}*.msg)
#   - No uncommitted code changes (checked below)
#   - No unchecked TODO items (checked below)
# If so, skip the completion checks entirely.
INBOX_DIR="$HOME/fang/inbox"
HAS_INBOX=0
if [ -d "$INBOX_DIR" ]; then
  # shellcheck disable=SC2086
  if ls "$INBOX_DIR"/*"${SESSION_NAME}"*.msg 2>/dev/null | grep -q . || \
     ls "$INBOX_DIR"/*"${PROJECT_NAME}"*.msg 2>/dev/null | grep -q .; then
    HAS_INBOX=1
  fi
fi

# ── Work completion checks ──

BLOCKED=false
REASONS=""

# Check 1: Uncommitted code changes (excludes .memorai/ — that's the stop-gate's job)
DIRTY=$(git diff --name-only 2>/dev/null | grep -v '\.memorai/' | head -5)
STAGED=$(git diff --cached --name-only 2>/dev/null | grep -v '\.memorai/' | head -5)
if [ -n "$DIRTY" ] || [ -n "$STAGED" ]; then
  BLOCKED=true
  CHANGES=""
  [ -n "$DIRTY" ] && CHANGES="modified: $(echo "$DIRTY" | tr '\n' ', ' | sed 's/,$//')"
  [ -n "$STAGED" ] && CHANGES="${CHANGES:+$CHANGES; }staged: $(echo "$STAGED" | tr '\n' ', ' | sed 's/,$//')"
  REASONS="${REASONS}  * Uncommitted changes: ${CHANGES}\n"
fi

# Check 2: TODO.md has unchecked items
if [ -f "TODO.md" ]; then
  # grep -c prints 0 AND exits 1 on no-match; the `|| echo 0` then appends a
  # second 0 on a new line. Take only the first line and strip whitespace so
  # `[ -gt ]` sees a single integer.
  UNCHECKED=$(grep -c '^\s*- \[ \]' TODO.md 2>/dev/null | head -n1 | tr -d '[:space:]')
  [[ "$UNCHECKED" =~ ^[0-9]+$ ]] || UNCHECKED=0
  if [ "$UNCHECKED" -gt 0 ]; then
    BLOCKED=true
    ITEMS=$(grep '^\s*- \[ \]' TODO.md | head -3 | sed 's/^/      /')
    REASONS="${REASONS}  * ${UNCHECKED} unchecked TODO items:\n${ITEMS}\n"
  fi
fi

# ── Roadmap-incomplete checks (AUTONOMOUS mode only) ──────────────────────
# Autonomous agents (the whole fleet per #65) run a self-driving feature loop:
# pick next roadmap item -> build -> commit -> LOOP. The dirty-tree + TODO.md
# checks above do NOT cover the *between-feature* gap: right after a clean
# feature commit the tree is clean and there is no TODO.md (roadmaps live in
# SPECS.md + Claude Code Tasks), so the agent would fall through to the standby
# verdict and STOP mid-product. Owner: in autonomous mode it must keep looping
# while the roadmap is incomplete. Two signals close that gap:
#
#   Check 3 (PRIMARY): the agent-owned sentinel `.roadmap-active`. The agent is
#     instructed (fang-spawn footer) to `touch .roadmap-active` while it has
#     roadmap work and to `rm` it ONLY when the product is genuinely complete or
#     every remaining item is owner-gated. Deterministic, agent-controlled, and
#     immune to Claude Code's task-store pruning (completed task JSONs are
#     deleted, so an empty task dir cannot itself prove "roadmap done").
#
#   Check 4 (SECONDARY): open (non-completed) Claude Code Tasks for THIS session.
#     Catches a stop mid-task-batch even if the sentinel is missing. Only fires
#     when a real open task exists, so it is safe for every (incl. classic) mode.
#
# Deadlock-safety: both checks only set BLOCKED=true; they feed the single
# existing BLOCKS counter and are bounded by Circuit breaker 2 (5 blocks ->
# allow stop). A genuinely-blocked agent (all remaining work owner-gated) is
# expected to fang-msg the owner and then `rm .roadmap-active` to idle cleanly,
# rather than burning the 5-block budget.

# Check 3: roadmap-active sentinel (PRIMARY autonomous signal)
ROADMAP_ACTIVE=false
if [ -f ".roadmap-active" ]; then
  ROADMAP_ACTIVE=true
  BLOCKED=true
  REASONS="${REASONS}  * Roadmap not complete: .roadmap-active sentinel is present.\n"
fi

# Check 4: open (non-completed) Claude Code Tasks for this session (SECONDARY)
# Task store: ~/.claude/tasks/<session_id>/<N>.json with {status: pending|
# in_progress|completed}. session_id comes from the stdin payload. Any parse or
# lookup failure degrades to OPEN_TASKS=0 (never blocks on uncertainty).
OPEN_TASKS=0
SESSION_ID=""
if [ -n "$HOOK_INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  else
    SESSION_ID=$(printf '%s' "$HOOK_INPUT" \
      | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
  fi
fi
TASK_DIR="$HOME/.claude/tasks/${SESSION_ID}"
if [ -n "$SESSION_ID" ] && [ -d "$TASK_DIR" ]; then
  for tf in "$TASK_DIR"/[0-9]*.json; do
    [ -f "$tf" ] || continue
    if command -v jq >/dev/null 2>&1; then
      st=$(jq -r '.status // empty' "$tf" 2>/dev/null)
    else
      st=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$tf" \
        | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    case "$st" in
      pending|in_progress) OPEN_TASKS=$((OPEN_TASKS + 1)) ;;
    esac
  done
fi
if [ "$OPEN_TASKS" -gt 0 ]; then
  BLOCKED=true
  REASONS="${REASONS}  * ${OPEN_TASKS} open Claude Code task(s) (pending/in_progress) remain.\n"
fi

# Standby verdict — if no inbox task AND no dirty work AND no TODOs, allow stop.
if [ "$HAS_INBOX" -eq 0 ] && [ "$BLOCKED" = "false" ]; then
  rm -f "$BLOCK_FILE"
  exit 0
fi

# If no inbox task but there IS dirty work, still block (agent abandoned work).
# If inbox task present and dirty work, block as before.

# ── Verdict ──
if [ "$BLOCKED" = "true" ]; then
  echo $(( BLOCKS + 1 )) > "$BLOCK_FILE"

  echo "" >&2
  echo "IDLE BLOCKED — Unfinished work detected (block $(( BLOCKS + 1 ))/${MAX_IDLE_BLOCKS}):" >&2
  echo -e "$REASONS" >&2

  if [ "$ROADMAP_ACTIVE" = "true" ] || [ "$OPEN_TASKS" -gt 0 ]; then
    # Roadmap-incomplete path (autonomous self-driving loop).
    echo "Your roadmap is NOT complete. Do NOT stop — continue the loop:" >&2
    echo "  1. Commit any pending code (git add + git commit) and verify it." >&2
    echo "  2. Pick the NEXT roadmap item (SPECS.md §6 / your Task list) and" >&2
    echo "     build it via the agent workflow. Do not ask 'what's next?'." >&2
    echo "  3. ONLY if every remaining item is genuinely owner-gated (blocked on" >&2
    echo "     a decision/credential/spend you cannot resolve): emit an owner" >&2
    echo "     question via 'fang-q' or '~/fang/display/fang-msg \$PROJECT ...'," >&2
    echo "     THEN 'rm .roadmap-active' — that is the ONLY clean way to idle." >&2
    echo "     (Being blocked-on-owner is distinct from lazy-stopping.)" >&2
  else
    echo "You are not done. Continue working on your assigned task:" >&2
    echo "  1. Commit all code changes (git add + git commit)" >&2
    echo "  2. Mark TODO items done (- [x]) or move to BACKLOG.md" >&2
    echo "  3. Verify your changes (curl, agent-browser, or tests)" >&2
    echo "  4. When truly finished, run /end to wrap up" >&2
  fi
  exit 2
fi

# All checks passed — reset block counter
rm -f "$BLOCK_FILE"
exit 0
