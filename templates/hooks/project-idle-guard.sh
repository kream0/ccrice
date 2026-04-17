#!/bin/bash
# Hook: Stop — Idle Guard (deterministic pre-checks)
# Purpose: Prevent agents from going idle with unfinished work.
# Runs BEFORE the prompt-type LLM evaluation and the session-hygiene stop-gate.
# Checks: uncommitted code changes, unchecked TODO items.
# Circuit breakers: context >= 20% (rotation needed), 5 consecutive blocks,
# no assigned inbox task (standby mode).

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")
SESSION_NAME="${FANG_WINDOW_NAME:-proj-${PROJECT_NAME}}"

# ── Circuit breaker 1: Context rotation ──
# At 40%+ (SOFT limit, 200K Opus 4.7), agent must wrap up — don't block, let it rotate
CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
CTX_PCT=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
CTX_PCT=${CTX_PCT:-0}
CTX_PCT=${CTX_PCT%%.*}
if [ "${CTX_PCT:-0}" -ge 40 ] 2>/dev/null; then
  rm -f "/tmp/${PROJECT_NAME}-idle-blocks"
  exit 0
fi

# ── Circuit breaker 2: Max consecutive blocks ──
# After 5 blocks, allow stop to prevent infinite loops
BLOCK_FILE="/tmp/${PROJECT_NAME}-idle-blocks"
BLOCKS=$(cat "$BLOCK_FILE" 2>/dev/null || echo 0)
[[ "$BLOCKS" =~ ^[0-9]+$ ]] || BLOCKS=0
if [ "$BLOCKS" -ge 5 ] 2>/dev/null; then
  echo "WARNING: Idle guard tripped $BLOCKS consecutive times. Allowing stop." >&2
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
  echo "IDLE BLOCKED — Unfinished work detected (${BLOCKS}/5):" >&2
  echo -e "$REASONS" >&2
  echo "You are not done. Continue working on your assigned task:" >&2
  echo "  1. Commit all code changes (git add + git commit)" >&2
  echo "  2. Mark TODO items done (- [x]) or move to BACKLOG.md" >&2
  echo "  3. Verify your changes (curl, agent-browser, or tests)" >&2
  echo "  4. When truly finished, run /end to wrap up" >&2
  exit 2
fi

# All checks passed — reset block counter
rm -f "$BLOCK_FILE"
exit 0
