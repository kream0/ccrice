#!/bin/bash

# Ralph Wiggum Supervisor (v2.1)
# Meta-loop that manages multiple Ralph cycles for unlimited autonomous operation
# Automatically restarts when context threshold is reached

set -euo pipefail

# State file paths (defined early for cleanup)
SUPERVISOR_STATE=".claude/ralph-supervisor.json"

# Cleanup function for trap handlers
cleanup() {
  local exit_code=$?
  # Update supervisor state on abnormal exit
  if [[ -f "$SUPERVISOR_STATE" ]] && [[ $exit_code -ne 0 ]]; then
    jq --argjson exit_code "$exit_code" \
      '.status = "interrupted" | .exit_code = $exit_code' \
      "$SUPERVISOR_STATE" > "$SUPERVISOR_STATE.tmp" 2>/dev/null && \
      mv "$SUPERVISOR_STATE.tmp" "$SUPERVISOR_STATE" || true
  fi
  exit $exit_code
}

# Set up trap handlers
trap cleanup EXIT ERR INT TERM

# Check for required dependencies
if ! command -v bun &>/dev/null; then
  echo "❌ Error: bun is required but not installed" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ Error: jq is required but not installed" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
MAX_RETRIES=2  # Retry transient failures up to N times
CONTEXT_THRESHOLD=60          # Start new cycle at this % (default: 60%)
MAX_CYCLES=10                 # Maximum cycles before stopping
MAX_ITERATIONS_PER_CYCLE=50   # Max iterations within a single cycle
COMPLETION_PROMISE=""
CHECKPOINT_INTERVAL=0
CHECKPOINT_MODE="notify"
PROMPT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Wiggum Supervisor (v2.1)
Manages multiple Ralph cycles for unlimited autonomous operation.

USAGE:
  run-supervisor.sh [OPTIONS] PROMPT...

OPTIONS:
  --context-threshold <n>      Start new cycle at this context % (default: 60)
  --max-cycles <n>             Maximum cycles before stopping (default: 10)
  --max-iterations <n>         Max iterations per cycle (default: 50)
  --completion-promise '<text>' Promise phrase to detect completion
  --checkpoint <n>             Pause every N iterations
  --checkpoint-mode <mode>     "pause" or "notify" (default: notify)
  -h, --help                   Show this help

HOW IT WORKS:
  1. Supervisor starts a Ralph headless loop (cycle 1)
  2. Each iteration, token usage is tracked via JSON output
  3. When context > threshold, cycle ends gracefully:
     - Handoff saved to Memorai
     - New cycle starts with fresh context
     - Handoff loaded for continuity
  4. Continues until task complete or max cycles reached

EXIT CODES:
  0   - Task completed successfully (promise detected)
  1   - Error occurred
  100 - Context threshold reached (used internally)

EXAMPLE:
  ./run-supervisor.sh \
    --max-cycles 5 \
    --context-threshold 60 \
    --completion-promise 'DONE' \
    "Build a REST API with full test coverage"

OUTPUT:
  - .claude/RALPH_STATUS.md    - Live status dashboard
  - .claude/RALPH_SUMMARY.md   - Final summary
  - Memorai entries            - All session data persisted
HELP_EOF
      exit 0
      ;;
    --context-threshold)
      CONTEXT_THRESHOLD="$2"
      shift 2
      ;;
    --max-cycles)
      MAX_CYCLES="$2"
      shift 2
      ;;
    --max-iterations)
      MAX_ITERATIONS_PER_CYCLE="$2"
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
    *)
      PROMPT="$PROMPT $1"
      shift
      ;;
  esac
done

PROMPT="${PROMPT# }"  # Trim leading space

if [[ -z "$PROMPT" ]]; then
  echo -e "${RED}Error: No prompt provided${NC}" >&2
  echo "   Usage: run-supervisor.sh [OPTIONS] PROMPT..." >&2
  exit 1
fi

# Generate a persistent session ID for the entire supervised run
SUPERVISOR_SESSION_ID="ralph-sup-$(date +%Y%m%d%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       RALPH WIGGUM SUPERVISOR v2.1                          ║${NC}"
echo -e "${CYAN}║       Autonomous Multi-Cycle Operation                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Session:${NC} $SUPERVISOR_SESSION_ID"
echo -e "${BLUE}Threshold:${NC} ${CONTEXT_THRESHOLD}%"
echo -e "${BLUE}Max Cycles:${NC} $MAX_CYCLES"
echo -e "${BLUE}Max Iterations/Cycle:${NC} $MAX_ITERATIONS_PER_CYCLE"
if [[ -n "$COMPLETION_PROMISE" ]]; then
  echo -e "${BLUE}Promise:${NC} $COMPLETION_PROMISE"
fi
echo ""

# Create supervisor state file (path defined at top for cleanup handler)
mkdir -p .claude

jq -n \
  --arg session_id "$SUPERVISOR_SESSION_ID" \
  --argjson max_cycles "$MAX_CYCLES" \
  --argjson context_threshold "$CONTEXT_THRESHOLD" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg objective "$PROMPT" \
  '{
    session_id: $session_id,
    max_cycles: $max_cycles,
    context_threshold: $context_threshold,
    started_at: $started_at,
    objective: $objective,
    current_cycle: 0,
    total_iterations: 0,
    status: "running"
  }' > "$SUPERVISOR_STATE"

# Track cycle number and total iterations
CYCLE=1
TOTAL_ITERATIONS=0
CYCLE_START_TIME=$(date +%s)

while [[ $CYCLE -le $MAX_CYCLES ]]; do
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  CYCLE $CYCLE / $MAX_CYCLES${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # Update supervisor state
  jq --argjson cycle "$CYCLE" --argjson total "$TOTAL_ITERATIONS" \
    '.current_cycle = $cycle | .total_iterations = $total' \
    "$SUPERVISOR_STATE" > "$SUPERVISOR_STATE.tmp" && mv "$SUPERVISOR_STATE.tmp" "$SUPERVISOR_STATE"

  # Load handoff from previous cycle (if exists)
  HANDOFF_CONTEXT=""
  if [[ $CYCLE -gt 1 ]]; then
    echo -e "${YELLOW}Loading handoff from cycle $((CYCLE - 1))...${NC}"
    HANDOFF_RESULT=$(bun run "${PLUGIN_ROOT}/scripts/load-cycle-handoff.ts" "$SUPERVISOR_SESSION_ID" 2>/dev/null || echo '{"found":false}')

    if echo "$HANDOFF_RESULT" | jq -e '.found == true' > /dev/null 2>&1; then
      HANDOFF_CONTEXT=$(echo "$HANDOFF_RESULT" | jq -r '.formatted_context // ""')
      echo -e "${GREEN}✓ Handoff loaded successfully${NC}"
    else
      echo -e "${YELLOW}⚠ No handoff found, starting fresh${NC}"
    fi
  fi

  # Build the cycle prompt
  if [[ -n "$HANDOFF_CONTEXT" ]]; then
    CYCLE_PROMPT="$HANDOFF_CONTEXT

$PROMPT"
  else
    CYCLE_PROMPT="$PROMPT"
  fi

  # Build run-headless command
  HEADLESS_CMD=("$SCRIPT_DIR/run-headless.sh"
    --max-iterations "$MAX_ITERATIONS_PER_CYCLE"
    --context-threshold "$CONTEXT_THRESHOLD"
    --cycle "$CYCLE"
    --supervisor-session "$SUPERVISOR_SESSION_ID"
  )

  if [[ -n "$COMPLETION_PROMISE" ]]; then
    HEADLESS_CMD+=(--completion-promise "$COMPLETION_PROMISE")
  fi
  if [[ $CHECKPOINT_INTERVAL -gt 0 ]]; then
    HEADLESS_CMD+=(--checkpoint "$CHECKPOINT_INTERVAL")
    HEADLESS_CMD+=(--checkpoint-mode "$CHECKPOINT_MODE")
  fi

  HEADLESS_CMD+=("$CYCLE_PROMPT")

  # Run the headless loop for this cycle
  set +e
  "${HEADLESS_CMD[@]}"
  EXIT_CODE=$?
  set -e

  # Calculate iterations this cycle (from state file if available)
  CYCLE_ITERATIONS=$(grep -oP 'iteration: \K\d+' .claude/ralph-loop.local.md 2>/dev/null || echo "0")
  TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + CYCLE_ITERATIONS))

  case $EXIT_CODE in
    0)
      # Task completed successfully
      CYCLE_END_TIME=$(date +%s)
      TOTAL_RUNTIME=$((CYCLE_END_TIME - CYCLE_START_TIME))

      echo ""
      echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
      echo -e "${GREEN}║                    TASK COMPLETED                            ║${NC}"
      echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "${GREEN}✓ Completion promise detected!${NC}"
      echo -e "${BLUE}Total cycles:${NC} $CYCLE"
      echo -e "${BLUE}Total iterations:${NC} $TOTAL_ITERATIONS"
      echo -e "${BLUE}Total runtime:${NC} ${TOTAL_RUNTIME}s"
      echo ""

      # Update supervisor state
      jq --argjson cycle "$CYCLE" --argjson total "$TOTAL_ITERATIONS" --argjson runtime "$TOTAL_RUNTIME" \
        '.status = "completed" | .current_cycle = $cycle | .total_iterations = $total | .runtime_seconds = $runtime' \
        "$SUPERVISOR_STATE" > "$SUPERVISOR_STATE.tmp" && mv "$SUPERVISOR_STATE.tmp" "$SUPERVISOR_STATE"

      exit 0
      ;;

    100)
      # Context threshold reached - save handoff and start new cycle
      echo ""
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${YELLOW}  CONTEXT THRESHOLD REACHED (${CONTEXT_THRESHOLD}%)${NC}"
      echo -e "${YELLOW}  Saving handoff and starting new cycle...${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

      # Save handoff
      HANDOFF_INPUT=$(jq -n \
        --arg session_id "$SUPERVISOR_SESSION_ID" \
        --argjson cycle_number "$CYCLE" \
        --arg original_objective "$PROMPT" \
        --argjson context_pct "$CONTEXT_THRESHOLD" \
        '{
          session_id: $session_id,
          cycle_number: $cycle_number,
          original_objective: $original_objective,
          context_pct: $context_pct
        }')

      echo "$HANDOFF_INPUT" | bun run "${PLUGIN_ROOT}/scripts/save-cycle-handoff.ts" 2>/dev/null || true

      echo -e "${GREEN}✓ Handoff saved${NC}"

      # Increment cycle
      CYCLE=$((CYCLE + 1))

      # Small delay before starting new cycle
      sleep 2
      ;;

    *)
      # Error occurred - check if we should retry
      RETRY_COUNT=${RETRY_COUNT:-0}
      RETRY_COUNT=$((RETRY_COUNT + 1))

      if [[ $RETRY_COUNT -le $MAX_RETRIES ]]; then
        # Transient failure - retry
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  TRANSIENT ERROR (exit code: $EXIT_CODE)${NC}"
        echo -e "${YELLOW}  Retry $RETRY_COUNT of $MAX_RETRIES in 5 seconds...${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        sleep 5
        # Don't increment cycle, retry same cycle
        continue
      fi

      # Max retries exceeded - fail
      echo ""
      echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
      echo -e "${RED}║              ERROR AFTER $MAX_RETRIES RETRIES                          ║${NC}"
      echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "${RED}Exit code: $EXIT_CODE${NC}"
      echo -e "${BLUE}Cycles completed:${NC} $((CYCLE - 1))"
      echo -e "${BLUE}Total iterations:${NC} $TOTAL_ITERATIONS"
      echo ""

      # Update supervisor state
      jq --argjson cycle "$CYCLE" --argjson total "$TOTAL_ITERATIONS" --argjson exit_code "$EXIT_CODE" \
        '.status = "error" | .current_cycle = $cycle | .total_iterations = $total | .exit_code = $exit_code' \
        "$SUPERVISOR_STATE" > "$SUPERVISOR_STATE.tmp" && mv "$SUPERVISOR_STATE.tmp" "$SUPERVISOR_STATE"

      exit $EXIT_CODE
      ;;
  esac

  # Reset retry counter on successful cycle progression
  RETRY_COUNT=0
done

# Max cycles reached
CYCLE_END_TIME=$(date +%s)
TOTAL_RUNTIME=$((CYCLE_END_TIME - CYCLE_START_TIME))

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║              MAX CYCLES REACHED ($MAX_CYCLES)                         ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Task may be incomplete. Review RALPH_SUMMARY.md for status.${NC}"
echo -e "${BLUE}Total iterations:${NC} $TOTAL_ITERATIONS"
echo -e "${BLUE}Total runtime:${NC} ${TOTAL_RUNTIME}s"
echo ""

# Update supervisor state
jq --argjson cycle "$MAX_CYCLES" --argjson total "$TOTAL_ITERATIONS" --argjson runtime "$TOTAL_RUNTIME" \
  '.status = "max_cycles" | .current_cycle = $cycle | .total_iterations = $total | .runtime_seconds = $runtime' \
  "$SUPERVISOR_STATE" > "$SUPERVISOR_STATE.tmp" && mv "$SUPERVISOR_STATE.tmp" "$SUPERVISOR_STATE"

exit 0
