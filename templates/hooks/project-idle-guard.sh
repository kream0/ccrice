#!/bin/bash
# Hook: Stop — Idle Guard (deterministic pre-checks)
# Purpose: Prevent agents from going idle with unfinished work.
# Runs BEFORE the prompt-type LLM evaluation and the session-hygiene stop-gate.
# Checks: uncommitted code changes, unchecked TODO items, AND (autonomous mode)
#         an incomplete roadmap — see "Roadmap-incomplete checks" below.
# Circuit breakers: 5 consecutive blocks (deadlock safety), no assigned inbox
# task (standby mode). Context-threshold rotation (Circuit breaker 1) is driven
# by the per-project context_mode flag: ENABLED for classic, SKIPPED for
# autonomous (native auto-compact owns context). See Circuit breaker 1 below.

# ── Pure decision function (autonomous roadmap gate) — #97 ─────────────────
# Extracted so it can be unit-tested in isolation (mirrors #56's
# detect_agent_coordinator_violation in fang-heartbeat.sh). It owns the ONE
# question: in autonomous mode, may the agent legitimately idle given the
# roadmap sentinel + gate-ledger state? It NEVER reads the filesystem, network,
# or git — all inputs are passed in, all outputs are a string.
#
# Args:
#   $1 = context_mode            ("autonomous" or anything else => classic)
#   $2 = roadmap_active_present  ("1" if .roadmap-active exists, else "0")
#   $3 = roadmap_gated_content   (full text of .roadmap-gated, "" if absent)
# Output (stdout):
#   ""        => the roadmap gate ALLOWS a stop (fall through to other checks)
#   <reason>  => a one-line block reason (caller must BLOCK the stop)
#
# Invariant (#97): in autonomous mode an agent may idle ONLY when the sentinel
# is absent AND a structured .roadmap-gated ledger records that EVERY remaining
# item is a genuine gate. Each non-blank, non-comment ledger line must be
# "TAG: justification" with TAG in {SPEND, CREDENTIAL, SUDO, ARCH}. Removing the
# sentinel ALONE is never enough, and "what's next?"-class items are never gates.
idle_gate_verdict() {
  local mode="$1" active="$2" gated="$3"

  # Classic mode: the roadmap gate does not apply — always allow fall-through.
  [ "$mode" = "autonomous" ] || { printf ''; return 0; }

  # Sentinel present => roadmap still has buildable work => BLOCK (keep looping).
  if [ "$active" = "1" ]; then
    printf 'Roadmap not complete: .roadmap-active sentinel is present.'
    return 0
  fi

  # Sentinel absent. The ONLY sanctioned way to idle now is a valid ledger.
  # Banned-question class (case-insensitive): never a legitimate gate.
  local banned="what'?s? *next|next priority|what should i (do|build)|which .*prioriti|^bilan|consolidated bilan"

  # No ledger (absent OR only blanks/comments) => removing the sentinel alone is
  # not enough => BLOCK.
  local has_item=0 line tag rest stripped
  while IFS= read -r line || [ -n "$line" ]; do
    stripped="${line#"${line%%[![:space:]]*}"}"   # ltrim
    [ -z "$stripped" ] && continue                  # blank
    case "$stripped" in '#'*) continue ;; esac      # comment
    has_item=1

    # Banned-question class anywhere on the line => BLOCK and name it.
    if printf '%s' "$line" | grep -qiE "$banned"; then
      printf 'Invalid .roadmap-gated line (banned "what-next"-class item, not a gate): %s' "$stripped"
      return 0
    fi

    # Must be "TAG: justification" with a recognized TAG and non-empty reason.
    tag="${stripped%%:*}"
    tag="${tag%"${tag##*[![:space:]]}"}"            # rtrim tag
    case "$stripped" in
      *:*) : ;;                                      # has a colon
      *)   printf 'Invalid .roadmap-gated line (no "TAG: justification" form): %s' "$stripped"
           return 0 ;;
    esac
    rest="${stripped#*:}"
    rest="${rest#"${rest%%[![:space:]]*}"}"          # ltrim justification
    case "$tag" in
      SPEND|CREDENTIAL|SUDO|ARCH) : ;;
      *) printf 'Invalid .roadmap-gated line (TAG must be SPEND|CREDENTIAL|SUDO|ARCH): %s' "$stripped"
         return 0 ;;
    esac
    if [ -z "$rest" ]; then
      printf 'Invalid .roadmap-gated line (missing justification after TAG): %s' "$stripped"
      return 0
    fi
  done <<EOF
$gated
EOF

  if [ "$has_item" -eq 0 ]; then
    printf '%s' "Sentinel .roadmap-active removed without recording why every remaining item is genuinely gated. Either 'touch .roadmap-active' and keep building, or write a valid .roadmap-gated ledger (one 'TAG: justification' per genuine gate; TAG in SPEND|CREDENTIAL|SUDO|ARCH)."
    return 0
  fi

  # Sentinel absent, ledger present, every line a valid genuine gate => ALLOW.
  printf ''
  return 0
}

# When sourced for unit tests, stop here — the caller wants the pure function
# only, not the live Stop-hook side effects (stdin read, cd, exits).
if [ "${IDLE_GUARD_SOURCE_ONLY:-}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

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

# Per-project context mode — single source of truth is the .context-mode
# sentinel materialized by fang-spawn from projects.json. Missing/unknown value
# defaults to "classic" so existing projects keep their pre-#65 behavior.
CONTEXT_MODE=$(cat ".claude/.context-mode" 2>/dev/null | tr -d '[:space:]')
[ "$CONTEXT_MODE" = "autonomous" ] || CONTEXT_MODE="classic"

# ── Progress / delegation awareness (false-positive killer) ────────────────
# The roadmap gate (Check 3) and the open-task gate (Check 4) below BLOCK on the
# bare presence of the `.roadmap-active` sentinel / an open task. But an
# autonomous agent legitimately DELEGATES a roadmap slice to a background
# sub-agent and YIELDS its main turn to wait for it — a correct pattern that
# looks identical to "agent gave up". On that quiet yield both Stop hooks
# false-fired, doubling "DON'T STOP" injections and burning the agent's context
# while it was, in fact, making progress.
#
# is_progressing() answers ONE question: is this session ACTIVELY progressing
# right now? It returns 0 (yes, progressing) if ANY of:
#   (a) a git commit within PROGRESS_WINDOW seconds, OR
#   (b) a source-tree file modified within PROGRESS_WINDOW seconds, OR
#   (c) a sub-agent was spawned within PROGRESS_WINDOW seconds (delegation-yield;
#       read from the lifecycle tracker's /tmp/<project>-agent-state.json).
# It returns 1 (not progressing) only when NONE hold. A 4th delegation signal —
# an open in_progress Claude Code Task for this session — is folded in at the
# gate (Check 3/4 below) where OPEN_TASKS is already computed, so we never read
# the task store twice.
#
# FAIL-SAFE: every probe is wrapped so a parse/lookup error degrades toward
# "progressing" (allow the quiet stop) — we never BLOCK on a check error. The
# 5-consecutive-block breaker (Circuit breaker 2) remains the backstop so a
# genuinely-parked agent is still re-engaged; this only removes the false
# positive on a working/delegating agent.
# PROGRESS_WINDOW is the recency horizon (seconds). Overridable via env for
# deterministic fixture testing (a genuine-stall test sets PROGRESS_WINDOW=0 so
# nothing counts as recent). Non-numeric/empty overrides fall back to 600.
PROGRESS_WINDOW="${PROGRESS_WINDOW:-600}"
[[ "$PROGRESS_WINDOW" =~ ^[0-9]+$ ]] || PROGRESS_WINDOW=600
is_progressing() {
  local now ct mtime spawn_ts state_file
  now=$(date +%s 2>/dev/null) || return 0   # clock unreadable -> assume progress

  # (a) recent git commit
  ct=$(git log -1 --format=%ct 2>/dev/null)
  if [[ "$ct" =~ ^[0-9]+$ ]] && [ "$(( now - ct ))" -lt "$PROGRESS_WINDOW" ]; then
    return 0
  fi

  # (b) newest source-tree file mtime (ignore VCS/dep/build dirs + dotfiles so a
  #     sentinel touch or .git write does not look like product progress)
  # NOTE: prune hidden entries with -name '.?*' (a dot + at least one char) — a
  # bare '.*' also matches the find ROOT node '.', which would prune the ENTIRE
  # tree and silently return no mtime (caught by the matrix harness).
  mtime=$(find . \
            \( -path ./.git -o -path ./node_modules -o -path ./dist \
               -o -path ./build -o -path ./.memorai -o -name '.?*' \) -prune -o \
            -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -n1)
  mtime=${mtime%%.*}
  if [[ "$mtime" =~ ^[0-9]+$ ]] && [ "$(( now - mtime ))" -lt "$PROGRESS_WINDOW" ]; then
    return 0
  fi

  # (c) recent sub-agent spawn (delegation-yield) — newest spawn timestamp from
  #     the PreToolUse[Agent] lifecycle tracker. ISO-8601 -> epoch via date.
  state_file="/tmp/${PROJECT_NAME}-agent-state.json"
  if [ -f "$state_file" ]; then
    if command -v jq >/dev/null 2>&1; then
      spawn_ts=$(jq -r '.spawns | max_by(.timestamp) | .timestamp // empty' "$state_file" 2>/dev/null)
    else
      spawn_ts=$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" \
                 | sed 's/.*"\([^"]*\)"$/\1/' | sort | tail -n1)
    fi
    if [ -n "$spawn_ts" ]; then
      local spawn_epoch
      spawn_epoch=$(date -d "$spawn_ts" +%s 2>/dev/null)
      if [[ "$spawn_epoch" =~ ^[0-9]+$ ]] && [ "$(( now - spawn_epoch ))" -lt "$PROGRESS_WINDOW" ]; then
        return 0
      fi
    fi
  fi

  return 1   # no recent commit, file change, spawn, or open task seen here
}

# ── Circuit breaker 1: Context rotation (CLASSIC mode only) ──
# classic    : at the SOFT limit (40% of 200K) allow the stop so a fresh
#              session can take over — the pre-#65 forced-rotation behavior.
# autonomous : SKIP. The agent runs on Claude Code's native auto-compact and is
#              told NOT to monitor context %; letting a context threshold trigger
#              `exit 0` here made autonomous agents (e.g. hotseat) STOP mid-loop
#              at ~40–50% with the product still incomplete. context_mode is now
#              the single control for this (replaces the #65 global neuter);
#              deadlock-safety is preserved by Circuit breaker 2 (5 blocks).
if [ "$CONTEXT_MODE" = "classic" ]; then
  CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
  CTX_PCT=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
  CTX_PCT=${CTX_PCT:-0}
  CTX_PCT=${CTX_PCT%%.*}
  if [ "${CTX_PCT:-0}" -ge 40 ] 2>/dev/null; then
    rm -f "/tmp/${PROJECT_NAME}-idle-blocks"
    exit 0
  fi
fi

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

# ── Progress / delegation awareness (computed BEFORE the completion checks) ──
# #124: the work-completion checks below (uncommitted code, unchecked TODO) and
# the roadmap/open-task gates further down must ALL be suppressed while the agent
# is actively PROGRESSING. Previously PROGRESSING was computed AFTER Check 1/2, so
# a delegating autonomous agent (read-only reviewer in flight, WIP pending that
# review per its CLAUDE.md implement->review->commit loop) was force-blocked by
# the unconditional uncommitted-changes gate even though the roadmap gate (Check
# 3) printed "actively progressing — allowing the quiet turn-end". That produced
# the contradictory "allowing ... / IDLE BLOCKED — Uncommitted changes" output the
# owner saw. We now compute PROGRESSING first and gate EVERY check on it.
#
# Open Claude Code Task detection. Task store: ~/.claude/tasks/<session_id>/<N>.json
# with {status: pending|in_progress|completed}. session_id comes from the stdin
# payload. Any parse/lookup failure degrades to 0 (never blocks on uncertainty).
# IN_PROGRESS_TASKS is tracked separately: an in_progress task means a sub-agent
# is ACTIVELY running for this session — a delegation-progress signal, not a
# stall. OPEN_TASKS = pending + in_progress (kept for the secondary gate).
OPEN_TASKS=0
IN_PROGRESS_TASKS=0
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
      in_progress) OPEN_TASKS=$((OPEN_TASKS + 1)); IN_PROGRESS_TASKS=$((IN_PROGRESS_TASKS + 1)) ;;
      pending)     OPEN_TASKS=$((OPEN_TASKS + 1)) ;;
    esac
  done
fi

# Progress / delegation verdict (false-positive killer). The agent is treated as
# actively progressing — and therefore allowed a QUIET turn-end — when EITHER a
# sub-agent is actively running (an in_progress Claude Code Task) OR is_progressing()
# found a recent commit / file edit / sub-agent spawn (< PROGRESS_WINDOW). Fail-safe:
# is_progressing() degrades toward "progressing" on any probe error, so a check
# failure never manufactures a false block — the 5-block breaker remains the
# parked-agent backstop.
PROGRESSING=false
if [ "$IN_PROGRESS_TASKS" -gt 0 ] || is_progressing; then
  PROGRESSING=true
fi

# ── Work completion checks ──

BLOCKED=false
REASONS=""

# Check 1: Uncommitted code changes (excludes .memorai/ — that's the stop-gate's job).
# #124: suppressed while the agent is actively PROGRESSING. WIP pending an in-flight
# read-only reviewer (the CLAUDE.md implement->review->commit loop) is delegation,
# not abandoned work — forcing a mid-loop commit fought a correctly-working agent.
# A genuine stall (not progressing) still blocks here exactly as before.
DIRTY=$(git diff --name-only 2>/dev/null | grep -v '\.memorai/' | head -5)
STAGED=$(git diff --cached --name-only 2>/dev/null | grep -v '\.memorai/' | head -5)
if [ "$PROGRESSING" != "true" ] && { [ -n "$DIRTY" ] || [ -n "$STAGED" ]; }; then
  BLOCKED=true
  CHANGES=""
  [ -n "$DIRTY" ] && CHANGES="modified: $(echo "$DIRTY" | tr '\n' ', ' | sed 's/,$//')"
  [ -n "$STAGED" ] && CHANGES="${CHANGES:+$CHANGES; }staged: $(echo "$STAGED" | tr '\n' ', ' | sed 's/,$//')"
  REASONS="${REASONS}  * Uncommitted changes: ${CHANGES}\n"
fi

# Check 2: TODO.md has unchecked items. Also progress-gated (#124) — a delegating
# agent mid-loop must not be force-blocked on a TODO it is actively working.
if [ "$PROGRESSING" != "true" ] && [ -f "TODO.md" ]; then
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

# ── Roadmap-incomplete checks ─────────────────────────────────────────────
# Autonomous agents run a self-driving feature loop: pick next roadmap item ->
# build -> commit -> LOOP. The dirty-tree + TODO.md checks above do NOT cover
# the *between-feature* gap: right after a clean feature commit the tree is
# clean and there is no TODO.md (roadmaps live in SPECS.md + Claude Code Tasks),
# so the agent would fall through to the standby verdict and STOP mid-product.
# In autonomous mode it must keep looping while the roadmap is incomplete.
#
#   Check 3 (PRIMARY, autonomous-only): the agent-owned roadmap gate. While the
#     sentinel `.roadmap-active` is present the agent MUST keep looping. The
#     #97 closure: removing the sentinel ALONE is NOT enough to idle — the agent
#     must ALSO produce a structured `.roadmap-gated` ledger proving EVERY
#     remaining item is a genuine gate (SPEND/CREDENTIAL/SUDO/ARCH), recorded
#     and auditable, not merely asserted by deleting a file. "What's next?"-class
#     items are never valid gates. All of this is decided by the pure
#     idle_gate_verdict() above; here we only gather inputs and apply the verdict.
#
#   Check 4 (SECONDARY, all modes): open (non-completed) Claude Code Tasks for
#     THIS session. Catches a stop mid-task-batch even if the gate allows. Only
#     fires when a real open task exists, so it is safe for every mode.
#
# Progress/delegation awareness (false-positive killer): BOTH gates are
# suppressed while the session is actively PROGRESSING — a recent commit/edit/
# sub-agent spawn (is_progressing) or an in_progress Claude Code Task. That is
# the delegation-yield case (the agent handed a slice to a sub-agent and yielded
# its turn to wait) which is correct behavior, not a stall, so it must NOT block.
# A genuine stall (sentinel present, no in_progress task, no recent activity)
# still blocks here exactly as before, preserving park-prevention.
#
# Deadlock-safety: both checks only set BLOCKED=true; they feed the single
# existing BLOCKS counter and are bounded by Circuit breaker 2 (5 blocks ->
# allow stop). A genuinely-blocked agent (all remaining work owner-gated) idles
# cleanly by writing a valid .roadmap-gated ledger, never by burning the budget.

# OPEN_TASKS / IN_PROGRESS_TASKS / SESSION_ID and the PROGRESSING verdict are now
# computed ABOVE the work-completion checks (#124) so Check 1/2 can be progress-
# gated consistently with Check 3/4 below. Nothing to recompute here.

# Check 3: roadmap gate (PRIMARY autonomous signal) — sentinel + gate ledger.
# The pure idle_gate_verdict() decides whether the sentinel/ledger state would
# block. We then APPLY that verdict ONLY when the agent is NOT actively
# progressing — a delegating/committing agent gets the quiet stop instead of a
# doubled "DON'T STOP" injection (the #56-class false positive).
ROADMAP_ACTIVE=false
ROADMAP_PRESENT=0
[ -f ".roadmap-active" ] && ROADMAP_PRESENT=1
GATED_CONTENT=""
[ -f ".roadmap-gated" ] && GATED_CONTENT=$(cat ".roadmap-gated" 2>/dev/null)
GATE_REASON=$(idle_gate_verdict "$CONTEXT_MODE" "$ROADMAP_PRESENT" "$GATED_CONTENT")
if [ -n "$GATE_REASON" ]; then
  if [ "$PROGRESSING" = "true" ]; then
    echo "IDLE GUARD: roadmap incomplete but agent is actively progressing (recent commit/edit/spawn or in_progress task) — allowing the quiet turn-end (delegation-yield, not a stall)." >&2
  else
    ROADMAP_ACTIVE=true
    BLOCKED=true
    REASONS="${REASONS}  * ${GATE_REASON}\n"
  fi
fi

# Check 4: open (non-completed) Claude Code Tasks for this session (SECONDARY).
# Catches a stop mid-task-batch even if the roadmap gate allowed. Suppressed
# while PROGRESSING (an in_progress task IS active delegation, and a fresh
# commit/edit/spawn means the batch is moving) so it cannot re-introduce the
# delegation-yield false positive the roadmap gate just cleared.
if [ "$OPEN_TASKS" -gt 0 ] && [ "$PROGRESSING" != "true" ]; then
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
    echo "  3. To idle LEGITIMATELY: removing .roadmap-active alone is NOT enough." >&2
    echo "     Write a structured ledger '.roadmap-gated' where every remaining item" >&2
    echo "     is a genuine gate, one per line as 'TAG: justification' with TAG in" >&2
    echo "     {SPEND, CREDENTIAL, SUDO, ARCH}. File each gate's question via 'fang-q'" >&2
    echo "     first. 'What's next?'/'next priority'/'bilan'-class items are NEVER" >&2
    echo "     valid gates. If buildable work remains, 'touch .roadmap-active' and keep" >&2
    echo "     building — that, or a valid ledger, are the ONLY clean ways to idle." >&2
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
