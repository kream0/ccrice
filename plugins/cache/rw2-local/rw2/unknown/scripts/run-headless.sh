#!/bin/bash

# Ralph Wiggum Headless Runner (v2 - with transcript access)
# Runs ralph-loop in headless mode using print mode with an external loop
# Now includes transcript analysis for memory/status updates

set -euo pipefail

# State file path (defined early for cleanup)
RALPH_STATE_FILE=".claude/ralph-loop.local.md"

# Cleanup function for trap handlers
cleanup() {
  local exit_code=$?
  # Remove temp/lock files but keep state file unless we completed successfully
  rm -f "${RALPH_STATE_FILE}.lock" ".claude/RALPH_PAUSED" 2>/dev/null || true
  exit $exit_code
}

# Set up trap handlers for cleanup on exit/error
trap cleanup EXIT ERR INT TERM

# Check for required dependencies
if ! command -v bun &>/dev/null; then
  echo "❌ Error: bun is required but not installed" >&2
  echo "   Install: curl -fsSL https://bun.sh/install | bash" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ Error: jq is required but not installed" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
MAX_ITERATIONS=50
COMPLETION_PROMISE=""
CHECKPOINT_INTERVAL=0
CHECKPOINT_MODE="notify"
CONTEXT_THRESHOLD=0           # 0 = disabled, otherwise exit at this % (for supervisor)
CURRENT_CYCLE=1
SUPERVISOR_SESSION=""
PROMPT=""

# Token tracking for context cycling
CUMULATIVE_INPUT_TOKENS=0
CUMULATIVE_OUTPUT_TOKENS=0
PEAK_CONTEXT_PCT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Loop Headless Runner (v2 - with transcript access)

USAGE:
  run-headless.sh [OPTIONS] PROMPT...

OPTIONS:
  --max-iterations <n>           Maximum iterations (default: 50)
  --completion-promise '<text>'  Promise phrase to detect completion
  --checkpoint <n>               Pause every N iterations (creates RALPH_PAUSED file)
  --checkpoint-mode <mode>       "pause" or "notify" (default: notify)
  -h, --help                     Show this help

DESCRIPTION:
  Runs a Ralph Wiggum loop headlessly using claude -p mode in an external
  loop. Now includes full transcript analysis:

  - Error detection and pattern analysis
  - Files modified tracking
  - Test status monitoring
  - Adaptive strategy updates
  - Memory file updates
  - Status dashboard updates

EXAMPLE:
  ./run-headless.sh --max-iterations 10 --completion-promise 'DONE' \
    "Build a REST API with tests"

OUTPUT:
  - .claude/RALPH_STATUS.md - Live status dashboard (updated each iteration)
  - .claude/RALPH_MEMORY.md - Session memory (updated each iteration)
  - .claude/RALPH_SUMMARY.md - Final summary (on completion)
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise)
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --checkpoint)
      CHECKPOINT_INTERVAL="$2"
      shift 2
      ;;
    --checkpoint-mode)
      CHECKPOINT_MODE="$2"
      shift 2
      ;;
    --context-threshold)
      CONTEXT_THRESHOLD="$2"
      shift 2
      ;;
    --cycle)
      CURRENT_CYCLE="$2"
      shift 2
      ;;
    --supervisor-session)
      SUPERVISOR_SESSION="$2"
      shift 2
      ;;
    *)
      PROMPT="$PROMPT $1"
      shift
      ;;
  esac
done

PROMPT="${PROMPT# }"  # Trim leading space

if [[ -z "$PROMPT" ]]; then
  echo "❌ Error: No prompt provided" >&2
  echo "   Usage: run-headless.sh [OPTIONS] PROMPT..." >&2
  exit 1
fi

# Compute project path for transcript access
PROJECT_PATH="$(pwd)"
# Claude Code encodes paths: /mnt/c/foo_bar/R&D -> -mnt-c-foo-bar-R-D
# Replace /, _, & with -
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's|[/_&]|-|g')
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
TRANSCRIPT_DIR="$CLAUDE_PROJECTS_DIR/$ENCODED_PATH"

echo "🚀 Starting Ralph Wiggum headless loop (v2 with transcript access)..."
echo "📁 Transcript dir: $TRANSCRIPT_DIR"

# Setup the loop (create state files)
SETUP_CMD=("$SCRIPT_DIR/setup-ralph-loop.sh" --max-iterations "$MAX_ITERATIONS" --checkpoint-mode "$CHECKPOINT_MODE")
if [[ -n "$COMPLETION_PROMISE" ]]; then
  SETUP_CMD+=(--completion-promise "$COMPLETION_PROMISE")
fi
if [[ $CHECKPOINT_INTERVAL -gt 0 ]]; then
  SETUP_CMD+=(--checkpoint "$CHECKPOINT_INTERVAL")
fi
SETUP_CMD+=("$PROMPT")

"${SETUP_CMD[@]}"

echo ""
echo "📊 Status: .claude/RALPH_STATUS.md"
echo "📝 Memory: .claude/RALPH_MEMORY.md"
echo ""

# State file paths (RALPH_STATE_FILE already defined at top for cleanup)
RALPH_MEMORY_FILE=".claude/RALPH_MEMORY.md"
RALPH_STATUS_FILE=".claude/RALPH_STATUS.md"

# Helper: Get most recent transcript (exclude agent- files)
get_latest_transcript() {
  if [[ -d "$TRANSCRIPT_DIR" ]]; then
    ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | grep -v 'agent-' | head -1 || echo ""
  else
    echo ""
  fi
}

# Helper: Parse YAML frontmatter value (handles CRLF line endings)
get_yaml_value() {
  # Strip CRLF, then parse
  sed 's/\r$//' "$1" 2>/dev/null | grep "^$2:" | sed "s/$2: *//" | sed 's/^"\(.*\)"$/\1/' | head -1
}

# Run the external loop
ITERATION=1
CURRENT_STRATEGY="explore"

# Extract session_id from state file (set once by setup-ralph-loop.sh)
SESSION_ID_FROM_STATE=$(get_yaml_value "$RALPH_STATE_FILE" "session_id")

while [[ $ITERATION -le $MAX_ITERATIONS ]]; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔄 Iteration $ITERATION / $MAX_ITERATIONS [$CURRENT_STRATEGY]"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Read memory for context
  CURRENT_STATUS=""
  NEXT_ACTIONS=""
  KEY_LEARNINGS=""
  if [[ -f "$RALPH_MEMORY_FILE" ]]; then
    # Extract sections from memory file
    CURRENT_STATUS=$(sed -n '/^## Current Status/,/^##/p' "$RALPH_MEMORY_FILE" | grep -v '^##' | head -5)
    NEXT_ACTIONS=$(sed -n '/^## Next Actions/,/^##/p' "$RALPH_MEMORY_FILE" | grep -v '^##' | head -5)
    KEY_LEARNINGS=$(sed -n '/^## Key Learnings/,/^##/p' "$RALPH_MEMORY_FILE" | grep -v '^##' | head -5)
  fi

  # Build the current prompt with full context
  CURRENT_PROMPT=$(cat <<EOF
=== RALPH ITERATION $ITERATION [$CURRENT_STRATEGY] ===

## YOUR MISSION (NEVER FORGET)
$PROMPT

## CURRENT STATUS
${CURRENT_STATUS:-"Starting iteration $ITERATION"}

## NEXT ACTIONS
${NEXT_ACTIONS:-"Continue working on the task"}

## KEY LEARNINGS (avoid repeating mistakes)
${KEY_LEARNINGS:-"None yet"}

## STRATEGY: $CURRENT_STRATEGY
$(case $CURRENT_STRATEGY in
  explore) echo "- Explore and understand the codebase/task";;
  focused) echo "- Focus on implementation, make steady progress";;
  cleanup) echo "- Final polish, fix remaining issues";;
  recovery) echo "- Errors detected! Debug and fix issues";;
esac)

## INSTRUCTIONS
- Check existing files to see previous progress
- Continue working on the task
- If you encounter errors, debug and fix them
- Update your approach based on key learnings
$(if [[ -n "$COMPLETION_PROMISE" ]]; then
  echo "- ONLY when task is TRULY complete, output: <promise>$COMPLETION_PROMISE</promise>"
fi)

===========================
EOF
)

  # Timestamp before running claude
  BEFORE_RUN=$(date +%s)

  # Use persistent session ID from state file (set once by setup-ralph-loop.sh)
  # This ensures all iterations share the same session ID for Memorai consistency
  SESSION_ID="$SESSION_ID_FROM_STATE"

  # Run claude with JSON output for token tracking
  RAW_OUTPUT=$(claude -p \
    --plugin-dir "$PLUGIN_ROOT" \
    --dangerously-skip-permissions \
    --session-id "$SESSION_ID" \
    --output-format json \
    "$CURRENT_PROMPT" 2>&1) || true

  # Parse JSON output for text and token metrics
  # Use jq for safe JSON construction in fallback to handle special characters
  PARSED_OUTPUT=$(echo "$RAW_OUTPUT" | bun run "${PLUGIN_ROOT}/scripts/parse-json-output.ts" 2>/dev/null)

  # Validate we got valid JSON, otherwise construct safe fallback
  if ! echo "$PARSED_OUTPUT" | jq -e '.text' &>/dev/null; then
    PARSED_OUTPUT=$(jq -n \
      --arg text "$RAW_OUTPUT" \
      '{text: $text, tokens: {input_tokens: 0, output_tokens: 0, total_tokens: 0, context_window: 200000, context_pct: 0}}')
  fi

  # Extract text for display
  OUTPUT=$(echo "$PARSED_OUTPUT" | jq -r '.text // ""' 2>/dev/null || echo "$RAW_OUTPUT")
  echo "$OUTPUT"
  echo ""

  # Extract token metrics (ensure integers for arithmetic)
  INPUT_TOKENS=$(echo "$PARSED_OUTPUT" | jq -r '.tokens.input_tokens // 0' 2>/dev/null | cut -d. -f1 || echo "0")
  OUTPUT_TOKENS=$(echo "$PARSED_OUTPUT" | jq -r '.tokens.output_tokens // 0' 2>/dev/null | cut -d. -f1 || echo "0")
  CONTEXT_PCT=$(echo "$PARSED_OUTPUT" | jq -r '.tokens.context_pct // 0' 2>/dev/null || echo "0")

  # Validate tokens are numeric
  [[ "$INPUT_TOKENS" =~ ^[0-9]+$ ]] || INPUT_TOKENS=0
  [[ "$OUTPUT_TOKENS" =~ ^[0-9]+$ ]] || OUTPUT_TOKENS=0

  # Update cumulative tokens
  CUMULATIVE_INPUT_TOKENS=$((CUMULATIVE_INPUT_TOKENS + INPUT_TOKENS))
  CUMULATIVE_OUTPUT_TOKENS=$((CUMULATIVE_OUTPUT_TOKENS + OUTPUT_TOKENS))

  # Track peak context usage - floor to integer (consistent, never triggers early)
  # Using awk for reliable float-to-int truncation
  CONTEXT_PCT_INT=$(echo "$CONTEXT_PCT" | awk '{printf "%d", $1}' 2>/dev/null || echo "0")
  [[ "$CONTEXT_PCT_INT" =~ ^[0-9]+$ ]] || CONTEXT_PCT_INT=0

  if [[ $CONTEXT_PCT_INT -gt $PEAK_CONTEXT_PCT ]]; then
    PEAK_CONTEXT_PCT=$CONTEXT_PCT_INT
  fi

  # Show token usage
  echo "📊 Tokens: input=$INPUT_TOKENS output=$OUTPUT_TOKENS (context: ${CONTEXT_PCT}%)"

  # Check context threshold (for supervisor mode)
  if [[ $CONTEXT_THRESHOLD -gt 0 ]] && [[ $CONTEXT_PCT_INT -ge $CONTEXT_THRESHOLD ]]; then
    echo ""
    echo "⚠️  CONTEXT THRESHOLD REACHED (${CONTEXT_PCT}% >= ${CONTEXT_THRESHOLD}%)"
    echo "    Signaling supervisor to start new cycle..."

    # Generate summary before exiting
    jq -n \
      --arg session_id "${SUPERVISOR_SESSION:-$SESSION_ID_FROM_STATE}" \
      --arg completion_reason "context_threshold" \
      --argjson final_iteration "$ITERATION" \
      --arg original_objective "$PROMPT" \
      --argjson context_pct "$CONTEXT_PCT_INT" \
      '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, original_objective: $original_objective, context_pct: $context_pct}' | \
      bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

    # Exit with special code 100 to signal supervisor
    exit 100
  fi

  # Find the transcript for this session
  TRANSCRIPT_PATH="$TRANSCRIPT_DIR/${SESSION_ID}.jsonl"

  # If specific session file not found, get most recent
  if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    TRANSCRIPT_PATH=$(get_latest_transcript)
  fi

  # === TRANSCRIPT ANALYSIS ===
  if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
    echo "📊 Analyzing transcript: $(basename "$TRANSCRIPT_PATH")"

    # 1. Analyze transcript
    ANALYSIS=$(bun run "${PLUGIN_ROOT}/scripts/analyze-transcript.ts" "$TRANSCRIPT_PATH" 2>/dev/null || \
      echo '{"errors":[],"repeated_errors":[],"files_modified":[],"tests_run":false,"tests_passed":false,"tests_failed":false,"phase_completions":[],"meaningful_changes":false}')

    # Parse analysis results
    ERRORS_COUNT=$(echo "$ANALYSIS" | jq '.errors | length' 2>/dev/null || echo "0")
    REPEATED_ERRORS=$(echo "$ANALYSIS" | jq '.repeated_errors | length' 2>/dev/null || echo "0")
    FILES_MODIFIED=$(echo "$ANALYSIS" | jq -r '.files_modified | join(", ")' 2>/dev/null || echo "")
    TESTS_PASSED=$(echo "$ANALYSIS" | jq -r '.tests_passed' 2>/dev/null || echo "false")
    TESTS_FAILED=$(echo "$ANALYSIS" | jq -r '.tests_failed' 2>/dev/null || echo "false")

    # 2. Build state JSON (session_id already extracted before loop)
    STARTED_AT=$(get_yaml_value "$RALPH_STATE_FILE" "started_at")
    STATE_JSON=$(jq -n \
      --arg active "true" \
      --argjson iteration "$ITERATION" \
      --argjson max_iterations "$MAX_ITERATIONS" \
      --arg completion_promise "$COMPLETION_PROMISE" \
      --arg started_at "${STARTED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
      --arg session_id "${SESSION_ID_FROM_STATE:-}" \
      --argjson checkpoint_interval "${CHECKPOINT_INTERVAL:-0}" \
      --arg checkpoint_mode "${CHECKPOINT_MODE:-notify}" \
      --arg current_strategy "$CURRENT_STRATEGY" \
      --argjson stuck_count "0" \
      --arg prompt_text "$PROMPT" \
      '{
        active: true,
        iteration: $iteration,
        max_iterations: $max_iterations,
        completion_promise: $completion_promise,
        started_at: $started_at,
        session_id: $session_id,
        checkpoint_interval: $checkpoint_interval,
        checkpoint_mode: $checkpoint_mode,
        strategy: { current: $current_strategy, changed_at: 0 },
        progress: { stuck_count: $stuck_count, velocity: "normal", last_meaningful_change: 0 },
        phases: [],
        prompt_text: $prompt_text
      }')

    # 3. Determine strategy
    STRATEGY_INPUT=$(jq -n \
      --argjson state "$STATE_JSON" \
      --argjson analysis "$ANALYSIS" \
      '{state: $state, analysis: $analysis}')

    STRATEGY_RESULT=$(echo "$STRATEGY_INPUT" | bun run "${PLUGIN_ROOT}/scripts/strategy-engine.ts" 2>/dev/null || \
      echo '{"strategy":"explore","reason":"Default","action":"continue","guidance":["Continue working"]}')

    NEW_STRATEGY=$(echo "$STRATEGY_RESULT" | jq -r '.strategy' 2>/dev/null || echo "explore")
    STRATEGY_REASON=$(echo "$STRATEGY_RESULT" | jq -r '.reason' 2>/dev/null || echo "")

    if [[ "$NEW_STRATEGY" != "$CURRENT_STRATEGY" ]]; then
      echo "🔄 Strategy changed: $CURRENT_STRATEGY → $NEW_STRATEGY ($STRATEGY_REASON)"
      CURRENT_STRATEGY="$NEW_STRATEGY"
    fi

    # 4. Update memory file
    MEMORY_INPUT=$(jq -n \
      --argjson state "$STATE_JSON" \
      --argjson analysis "$ANALYSIS" \
      '{state: $state, analysis: $analysis}')

    echo "$MEMORY_INPUT" | bun run "${PLUGIN_ROOT}/scripts/update-memory.ts" "$RALPH_MEMORY_FILE" 2>/dev/null || true

    # 5. Update status dashboard
    STATUS_INPUT=$(jq -n \
      --argjson state "$STATE_JSON" \
      --argjson analysis "$ANALYSIS" \
      --argjson strategy "$STRATEGY_RESULT" \
      '{state: $state, analysis: $analysis, strategy: $strategy}')

    echo "$STATUS_INPUT" | bun run "${PLUGIN_ROOT}/scripts/update-status.ts" "$RALPH_STATUS_FILE" 2>/dev/null || true

    # Show quick status
    if [[ "$ERRORS_COUNT" -gt 0 ]]; then
      echo "⚠️  Errors detected: $ERRORS_COUNT"
    fi
    if [[ -n "$FILES_MODIFIED" ]]; then
      echo "📝 Files modified: $FILES_MODIFIED"
    fi
    if [[ "$TESTS_PASSED" == "true" ]]; then
      echo "✅ Tests passed"
    elif [[ "$TESTS_FAILED" == "true" ]]; then
      echo "❌ Tests failed"
    fi
  else
    echo "⚠️  No transcript found for analysis"
  fi

  # Check for completion promise
  if [[ -n "$COMPLETION_PROMISE" ]]; then
    if echo "$OUTPUT" | grep -qF "<promise>$COMPLETION_PROMISE</promise>"; then
      echo ""
      echo "✅ Completion promise detected: $COMPLETION_PROMISE"

      # Generate summary
      # Build summary input with session_id and objective
      jq -n \
        --arg session_id "$SESSION_ID_FROM_STATE" \
        --arg completion_reason "promise" \
        --argjson final_iteration "$ITERATION" \
        --arg original_objective "$PROMPT" \
        '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, original_objective: $original_objective}' | \
        bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

      rm -f "$RALPH_STATE_FILE"
      echo "📋 Summary: .claude/RALPH_SUMMARY.md"
      exit 0
    fi
  fi

  # Update iteration and strategy in state file with locking and verification
  NEXT_ITERATION=$((ITERATION + 1))
  LOCK_FILE="${RALPH_STATE_FILE}.lock"
  TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"

  (
    # Acquire exclusive lock
    if ! flock -x -w 5 200; then
      echo "⚠️  Could not acquire lock on state file" >&2
    else
      # Validate strategy value
      case "$CURRENT_STRATEGY" in
        explore|focused|cleanup|recovery) ;;
        *) CURRENT_STRATEGY="explore" ;;
      esac

      # Use # as delimiter and write to temp file first
      sed -e "s#^iteration: .*#iteration: $NEXT_ITERATION#" \
          -e "s#^  current: .*#  current: \"$CURRENT_STRATEGY\"#" \
          "$RALPH_STATE_FILE" > "$TEMP_FILE"

      # Verify sed succeeded before moving
      if [[ -s "$TEMP_FILE" ]]; then
        mv "$TEMP_FILE" "$RALPH_STATE_FILE"
      else
        echo "⚠️  sed produced empty file, keeping original" >&2
        rm -f "$TEMP_FILE"
      fi
    fi
  ) 200>"$LOCK_FILE"
  rm -f "$LOCK_FILE"

  # Check for checkpoint (pause mode) - use atomic flag file operations
  if [[ $CHECKPOINT_INTERVAL -gt 0 ]] && [[ $((ITERATION % CHECKPOINT_INTERVAL)) -eq 0 ]]; then
    if [[ "$CHECKPOINT_MODE" == "pause" ]]; then
      echo ""
      echo "⏸️  Checkpoint at iteration $ITERATION"
      echo "    To continue, run: rm .claude/RALPH_PAUSED"
      touch ".claude/RALPH_PAUSED"
      # Wait with inotifywait if available, otherwise poll
      if command -v inotifywait &>/dev/null; then
        inotifywait -e delete ".claude/RALPH_PAUSED" 2>/dev/null || true
      else
        while [[ -f ".claude/RALPH_PAUSED" ]]; do
          sleep 1
        done
      fi
      echo "▶️  Resuming..."
    else
      echo "📍 Checkpoint: iteration $ITERATION"
    fi
  fi

  # Update shell iteration counter (sync with state file)
  ITERATION=$NEXT_ITERATION
  echo ""
done

echo ""
echo "🛑 Max iterations ($MAX_ITERATIONS) reached"

# Generate summary
# Build summary input with session_id and objective
jq -n \
  --arg session_id "$SESSION_ID_FROM_STATE" \
  --arg completion_reason "max_iterations" \
  --argjson final_iteration "$MAX_ITERATIONS" \
  --arg original_objective "$PROMPT" \
  '{session_id: $session_id, completion_reason: $completion_reason, final_iteration: $final_iteration, original_objective: $original_objective}' | \
  bun run "${PLUGIN_ROOT}/scripts/generate-summary.ts" ".claude/RALPH_SUMMARY.md" 2>/dev/null || true

rm -f "$RALPH_STATE_FILE"
echo "📋 Summary: .claude/RALPH_SUMMARY.md"
