#!/bin/bash

# Ralph Wiggum Stop Hook (Memorai Edition)
# Prevents session exit when a ralph-loop is active
# All session memory stored in memorai

set -euo pipefail

# Cleanup function for trap handlers
cleanup() {
  local exit_code=$?
  # Remove any temp files we may have created
  rm -f "${RALPH_STATE_FILE:-}.tmp.$$" "${RALPH_STATE_FILE:-}.lock" 2>/dev/null || true
  exit $exit_code
}

# Set up trap handlers for cleanup on exit/error
trap cleanup EXIT ERR INT TERM

# Check for required dependencies
if ! command -v bun &>/dev/null; then
  echo "⚠️  Ralph loop: bun is required but not installed" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "⚠️  Ralph loop: jq is required but not installed" >&2
  exit 0
fi

# Get plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Paths
RALPH_STATE_FILE=".claude/ralph-loop.local.md"
RALPH_STATUS_FILE=".claude/RALPH_STATUS.md"
RALPH_NUDGE_FILE=".claude/RALPH_NUDGE.md"

# Check if ralph-loop is active
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Parse markdown frontmatter (YAML between ---)
# Handles both LF and CRLF line endings (WSL compatibility)
parse_frontmatter() {
  # Convert CRLF to LF, then parse
  sed 's/\r$//' "$1" | sed -n '/^---$/,/^---$/{ /^---$/d; p; }'
}

get_yaml_value() {
  # Strip CRLF, then parse value
  echo "$1" | tr -d '\r' | grep "^$2:" | sed "s/$2: *//" | sed 's/^"\(.*\)"$/\1/'
}

get_yaml_nested_value() {
  # Strip CRLF, then parse nested value
  echo "$1" | tr -d '\r' | grep "^  $2:" | sed "s/  $2: *//" | sed 's/^"\(.*\)"$/\1/'
}

FRONTMATTER=$(parse_frontmatter "$RALPH_STATE_FILE")
ITERATION=$(get_yaml_value "$FRONTMATTER" "iteration")
MAX_ITERATIONS=$(get_yaml_value "$FRONTMATTER" "max_iterations")
COMPLETION_PROMISE=$(get_yaml_value "$FRONTMATTER" "completion_promise")
STARTED_AT=$(get_yaml_value "$FRONTMATTER" "started_at")
SESSION_ID=$(get_yaml_value "$FRONTMATTER" "session_id")
CHECKPOINT_INTERVAL=$(get_yaml_value "$FRONTMATTER" "checkpoint_interval")
CHECKPOINT_MODE=$(get_yaml_value "$FRONTMATTER" "checkpoint_mode")
CYCLE_NUMBER=$(get_yaml_value "$FRONTMATTER" "cycle_number")
CURRENT_STRATEGY=$(get_yaml_nested_value "$FRONTMATTER" "current")
STUCK_COUNT=$(get_yaml_nested_value "$FRONTMATTER" "stuck_count")

# Default cycle_number to 1 if not set (backwards compatibility)
if [[ -z "$CYCLE_NUMBER" ]] || [[ ! "$CYCLE_NUMBER" =~ ^[0-9]+$ ]]; then
  CYCLE_NUMBER=1
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: State file corrupted (iteration: '$ITERATION')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Validate session ID is present (required for memorai integration)
if [[ -z "$SESSION_ID" ]]; then
  echo "⚠️  Ralph loop: Missing session_id in state file" >&2
  # Generate a new session ID to prevent data loss
  SESSION_ID="ralph-$(date +%Y%m%d%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)"
  echo "    Generated new session_id: $SESSION_ID" >&2
fi

# Extract prompt text early (needed for generate-summary calls before line 162)
PROMPT_TEXT_EARLY=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached."

  # Generate final summary (include original_objective for proper summary)
  jq -n \
    --arg session_id "$SESSION_ID" \
    --arg completion_reason "max_iterations" \
    --argjson final_iteration "$ITERATION" \
    --arg original_objective "$PROMPT_TEXT_EARLY" \
    '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, original_objective: $original_objective}' | \
    bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Ralph loop: Transcript file not found: $TRANSCRIPT_PATH" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Check for assistant messages
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Ralph loop: No assistant messages in transcript" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Extract last assistant message
LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>/dev/null || echo "")

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Ralph loop: Empty assistant message" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Check for completion promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>"

    # Generate final summary (include original_objective for proper summary)
    jq -n \
      --arg session_id "$SESSION_ID" \
      --arg completion_reason "promise" \
      --argjson final_iteration "$ITERATION" \
      --arg original_objective "$PROMPT_TEXT_EARLY" \
      '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, original_objective: $original_objective}' | \
      bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

    rm "$RALPH_STATE_FILE"
    exit 0
  fi
fi

# === ENHANCED PROCESSING ===

# 1. Analyze transcript
ANALYSIS=$(bun run "${PLUGIN_ROOT}/scripts/analyze-transcript.ts" "$TRANSCRIPT_PATH" 2>/dev/null || echo '{"errors":[],"repeated_errors":[],"files_modified":[],"tests_run":false,"tests_passed":false,"tests_failed":false,"phase_completions":[],"meaningful_changes":false}')

# 2. Build state JSON for scripts (now includes session_id)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

STATE_JSON=$(jq -n \
  --arg active "true" \
  --argjson iteration "$ITERATION" \
  --argjson max_iterations "$MAX_ITERATIONS" \
  --arg completion_promise "$COMPLETION_PROMISE" \
  --arg started_at "${STARTED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
  --arg session_id "${SESSION_ID:-}" \
  --argjson checkpoint_interval "${CHECKPOINT_INTERVAL:-0}" \
  --arg checkpoint_mode "${CHECKPOINT_MODE:-notify}" \
  --arg current_strategy "${CURRENT_STRATEGY:-explore}" \
  --argjson stuck_count "${STUCK_COUNT:-0}" \
  --arg prompt_text "$PROMPT_TEXT" \
  '{
    active: true,
    iteration: $iteration,
    max_iterations: $max_iterations,
    completion_promise: $completion_promise,
    started_at: $started_at,
    session_id: $session_id,
    checkpoint_interval: $checkpoint_interval,
    checkpoint_mode: $checkpoint_mode,
    strategy: {
      current: $current_strategy,
      changed_at: 0
    },
    progress: {
      stuck_count: $stuck_count,
      velocity: "normal",
      last_meaningful_change: 0
    },
    phases: [],
    prompt_text: $prompt_text
  }')

# 3. Determine strategy
STRATEGY_INPUT=$(jq -n \
  --argjson state "$STATE_JSON" \
  --argjson analysis "$ANALYSIS" \
  '{state: $state, analysis: $analysis}')

STRATEGY=$(echo "$STRATEGY_INPUT" | bun run "${PLUGIN_ROOT}/scripts/strategy-engine.ts" 2>/dev/null || echo '{"strategy":"explore","reason":"Default","action":"continue","guidance":["Continue working"]}')

NEW_STRATEGY=$(echo "$STRATEGY" | jq -r '.strategy')

# 4. Update memory in memorai
MEMORY_INPUT=$(jq -n \
  --argjson state "$STATE_JSON" \
  --argjson analysis "$ANALYSIS" \
  '{state: $state, analysis: $analysis}')

echo "$MEMORY_INPUT" | bun run "${PLUGIN_ROOT}/scripts/update-memory.ts" 2>/dev/null || true

# 5. Update status dashboard
STATUS_INPUT=$(jq -n \
  --argjson state "$STATE_JSON" \
  --argjson analysis "$ANALYSIS" \
  --argjson strategy "$STRATEGY" \
  '{state: $state, analysis: $analysis, strategy: $strategy}')

echo "$STATUS_INPUT" | bun run "${PLUGIN_ROOT}/scripts/update-status.ts" "$RALPH_STATUS_FILE" 2>/dev/null || true

# 6. Check for nudge file (one-time instruction)
NUDGE_CONTENT=""
if [[ -f "$RALPH_NUDGE_FILE" ]]; then
  NUDGE_CONTENT=$(cat "$RALPH_NUDGE_FILE")
  rm "$RALPH_NUDGE_FILE"
fi

# 7. Check for checkpoint
NEXT_ITERATION=$((ITERATION + 1))
IS_CHECKPOINT=false

if [[ "${CHECKPOINT_INTERVAL:-0}" -gt 0 ]]; then
  if (( NEXT_ITERATION % CHECKPOINT_INTERVAL == 0 )); then
    IS_CHECKPOINT=true
  fi
fi

# 8. Build enhanced context (session_id passed in state)
CONTEXT_INPUT=$(jq -n \
  --argjson state "$STATE_JSON" \
  --argjson strategy "$STRATEGY" \
  --argjson analysis "$ANALYSIS" \
  --arg nudge_content "$NUDGE_CONTENT" \
  '{
    state: $state,
    strategy: $strategy,
    analysis: $analysis,
    nudge_content: $nudge_content
  }')

ENHANCED_PROMPT=$(echo "$CONTEXT_INPUT" | bun run "${PLUGIN_ROOT}/scripts/build-context.ts" 2>/dev/null || echo "$PROMPT_TEXT")

# 9. Update iteration and strategy in state file
# SECURITY: Validate NEW_STRATEGY is one of the allowed values
case "$NEW_STRATEGY" in
  explore|focused|cleanup|recovery) ;;
  *)
    echo "⚠️  Ralph loop: Invalid strategy '$NEW_STRATEGY', defaulting to 'explore'" >&2
    NEW_STRATEGY="explore"
    ;;
esac

# Use file locking to prevent race conditions during state updates
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
LOCK_FILE="${RALPH_STATE_FILE}.lock"

(
  # Acquire exclusive lock (wait up to 5 seconds)
  if ! flock -x -w 5 200; then
    echo "⚠️  Ralph loop: Could not acquire lock on state file" >&2
    exit 1
  fi

  # Use # as sed delimiter to avoid issues with special characters
  sed -e "s#^iteration: .*#iteration: $NEXT_ITERATION#" \
      -e "s#^  current: .*#  current: \"$NEW_STRATEGY\"#" \
      "$RALPH_STATE_FILE" > "$TEMP_FILE"

  # Verify sed succeeded before moving
  if [[ -s "$TEMP_FILE" ]]; then
    mv "$TEMP_FILE" "$RALPH_STATE_FILE"
  else
    echo "⚠️  Ralph loop: sed produced empty file, keeping original" >&2
    rm -f "$TEMP_FILE"
  fi
) 200>"$LOCK_FILE"

# Clean up lock file
rm -f "$LOCK_FILE"

# 10. Handle checkpoint (pause mode)
if [[ "$IS_CHECKPOINT" == "true" ]] && [[ "${CHECKPOINT_MODE:-notify}" == "pause" ]]; then
  # Create checkpoint file
  cat > ".claude/RALPH_CHECKPOINT.md" <<EOF
# Checkpoint at Iteration $NEXT_ITERATION

Ralph has paused for your review.

## How to Continue

1. Review the status: \`cat .claude/RALPH_STATUS.md\`
2. Query past sessions: \`/ralph-recall <query>\`
3. Optionally send guidance: \`/ralph-nudge "your instruction"\`
4. Resume: \`/ralph-checkpoint continue\`

Or to stop: \`/cancel-ralph\`
EOF

  echo "⏸️  Ralph checkpoint at iteration $NEXT_ITERATION - awaiting /ralph-checkpoint continue"

  # Block until checkpoint file is removed
  # "callback" is displayed, "systemMessage" is injected silently
  jq -n \
    --arg msg "⏸️ Checkpoint at iteration $NEXT_ITERATION. Review .claude/RALPH_CHECKPOINT.md and run /ralph-checkpoint continue to resume." \
    '{
      "decision": "block",
      "callback": "Checkpoint paused",
      "systemMessage": $msg
    }'
  exit 0
fi

# 11. Build system message
ERRORS_COUNT=$(echo "$ANALYSIS" | jq '.errors | length')
if [[ "$ERRORS_COUNT" -gt 0 ]]; then
  ERROR_INFO=" | ⚠️ $ERRORS_COUNT error(s)"
else
  ERROR_INFO=""
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="🔄 Ralph #$NEXT_ITERATION [$NEW_STRATEGY]$ERROR_INFO | Done? <promise>$COMPLETION_PROMISE</promise>"
else
  SYSTEM_MSG="🔄 Ralph #$NEXT_ITERATION [$NEW_STRATEGY]$ERROR_INFO"
fi

# Add nudge notification if present
if [[ -n "$NUDGE_CONTENT" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | 📬 Nudge received"
fi

# Add checkpoint notification
if [[ "$IS_CHECKPOINT" == "true" ]] && [[ "${CHECKPOINT_MODE:-notify}" == "notify" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | 📍 Checkpoint"
fi

# === TUI MODE CONTEXT TRACKING ===
# Estimate tokens from transcript and detect context threshold

CONTEXT_THRESHOLD=60  # 60% threshold for TUI mode

# Estimate tokens from transcript size (roughly 4 chars per token)
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  TRANSCRIPT_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
  ESTIMATED_TOKENS=$((TRANSCRIPT_SIZE / 4))
  CONTEXT_WINDOW=200000  # Opus/Sonnet context window
  THRESHOLD_TOKENS=$((CONTEXT_WINDOW * CONTEXT_THRESHOLD / 100))
  ESTIMATED_PCT=$((ESTIMATED_TOKENS * 100 / CONTEXT_WINDOW))

  if [[ $ESTIMATED_TOKENS -gt $THRESHOLD_TOKENS ]]; then
    echo ""
    echo "⚠️  CONTEXT THRESHOLD ESTIMATED (${ESTIMATED_PCT}% >= ${CONTEXT_THRESHOLD}%)"
    echo "    Saving handoff for cycle restart..."

    # Save handoff to memorai (use current cycle number, not hardcoded)
    HANDOFF_INPUT=$(jq -n \
      --arg session_id "$SESSION_ID" \
      --argjson cycle_number "$CYCLE_NUMBER" \
      --arg original_objective "$PROMPT_TEXT" \
      --argjson context_pct "$ESTIMATED_PCT" \
      '{
        session_id: $session_id,
        cycle_number: $cycle_number,
        original_objective: $original_objective,
        context_pct: $context_pct
      }')

    echo "$HANDOFF_INPUT" | bun run "${PLUGIN_ROOT}/scripts/save-cycle-handoff.ts" 2>/dev/null || true

    # Generate summary before restart (include original_objective for proper summary)
    jq -n \
      --arg session_id "$SESSION_ID" \
      --arg completion_reason "context_threshold" \
      --argjson final_iteration "$ITERATION" \
      --argjson context_pct "$ESTIMATED_PCT" \
      --arg original_objective "$PROMPT_TEXT" \
      '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, context_pct: $context_pct, original_objective: $original_objective}' | \
      bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

    # Clean up state file
    rm -f "$RALPH_STATE_FILE"

    # Output cycle restart marker
    echo ""
    echo "<ralph-cycle-restart/>"
    echo "Context at ~${ESTIMATED_TOKENS} tokens (~${ESTIMATED_PCT}%). Run /ralph-resume to continue with fresh context."
    exit 0
  fi
fi

# Output JSON to block the stop and feed enhanced prompt back
# Note: "callback" gets displayed as error message - keep it minimal
# The actual prompt goes in "systemMessage" which is injected silently
FULL_MSG="$SYSTEM_MSG

$ENHANCED_PROMPT"

jq -n \
  --arg msg "$FULL_MSG" \
  '{
    "decision": "block",
    "callback": "Loop continuing...",
    "systemMessage": $msg
  }'

exit 0
