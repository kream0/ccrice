#!/bin/bash
# Hook: PostToolUse[Agent] (Project)
# Purpose: Validate agent output has structured report format.
# Non-blocking (PostToolUse), but warns if output is unstructured.
# Also marks review-needed if implementer ran.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")
INPUT=$(cat)

AGENT_OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.text // .tool_result // ""' 2>/dev/null | head -c 2000)
STATE_FILE="/tmp/${PROJECT_NAME}-agent-state.json"

# Check for structured report markers
HAS_STRUCTURE=false
if echo "$AGENT_OUTPUT" | grep -qE "(TASK COMPLETE|REVIEW COMPLETE|TEST COMPLETE|Status:|Issues found:|Tests run:)"; then
  HAS_STRUCTURE=true
fi

if [ "$HAS_STRUCTURE" = "false" ]; then
  echo "WARNING: Agent output missing structured report format." >&2
  echo "Expected one of: TASK COMPLETE, REVIEW COMPLETE, TEST COMPLETE" >&2
  echo "With fields: Status, Files modified, Changes, Validation" >&2
fi

# If an implementer just finished, flag that review is needed
if [ -f "$STATE_FILE" ]; then
  IMPL_RAN=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
if state.get('implementer_ran') and not state.get('reviewer_ran'):
    print('true')
else:
    print('false')
" 2>/dev/null)

  if [ "$IMPL_RAN" = "true" ]; then
    echo "REMINDER: Implementer completed work. Spawn a reviewer agent before ending the session." >&2
  fi
fi

exit 0
