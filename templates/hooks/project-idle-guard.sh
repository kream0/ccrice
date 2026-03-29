#!/bin/bash
# Hook: Stop — Idle Guard (deterministic pre-checks)
# Purpose: Prevent agents from going idle with unfinished work.
# Runs BEFORE the prompt-type LLM evaluation and the session-hygiene stop-gate.
# Checks: uncommitted code changes, unchecked TODO items.
# Circuit breakers: context >= 20% (rotation needed), 5 consecutive blocks.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")

# ── Circuit breaker 1: Context rotation ──
# At 20%+, agent must rotate — don't block, let it wrap up
CTX_FILE="/tmp/${PROJECT_NAME}-context-pct"
CTX_PCT=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
CTX_PCT=${CTX_PCT:-0}
if [ "${CTX_PCT:-0}" -ge 20 ] 2>/dev/null; then
  rm -f "/tmp/${PROJECT_NAME}-idle-blocks"
  exit 0
fi

# ── Circuit breaker 2: Max consecutive blocks ──
# After 5 blocks, allow stop to prevent infinite loops
BLOCK_FILE="/tmp/${PROJECT_NAME}-idle-blocks"
BLOCKS=$(cat "$BLOCK_FILE" 2>/dev/null || echo 0)
if [ "$BLOCKS" -ge 5 ] 2>/dev/null; then
  echo "WARNING: Idle guard tripped $BLOCKS consecutive times. Allowing stop." >&2
  rm -f "$BLOCK_FILE"
  exit 0
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
  UNCHECKED=$(grep -c '^\s*- \[ \]' TODO.md 2>/dev/null || true)
  UNCHECKED=${UNCHECKED:-0}
  if [ "$UNCHECKED" -gt 0 ]; then
    BLOCKED=true
    ITEMS=$(grep '^\s*- \[ \]' TODO.md | head -3 | sed 's/^/      /')
    REASONS="${REASONS}  * ${UNCHECKED} unchecked TODO items:\n${ITEMS}\n"
  fi
fi

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
