#!/bin/bash
# Hook: PreToolUse[Agent] (Project)
# Purpose: Log agent spawns and track delegation state.
# Creates /tmp/<project>-agent-state.json tracking which agents have run.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME=$(basename "$(pwd)")
INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // .tool_input.type // "unknown"' 2>/dev/null)
AGENT_DESC=$(echo "$INPUT" | jq -r '.tool_input.description // "no description"' 2>/dev/null)
STATE_FILE="/tmp/${PROJECT_NAME}-agent-state.json"

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"spawns":[],"implementer_ran":false,"reviewer_ran":false,"tester_ran":false}' > "$STATE_FILE"
fi

# Record the spawn
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CURRENT=$(cat "$STATE_FILE")

# Update the appropriate flag based on agent prompt content or description
UPDATED=$(echo "$CURRENT" | python3 -c "
import sys, json
state = json.load(sys.stdin)
agent_type = '$AGENT_TYPE'
desc = '$AGENT_DESC'.lower()

# Track spawn
state['spawns'].append({
    'type': agent_type,
    'description': '$AGENT_DESC',
    'timestamp': '$TIMESTAMP'
})

# Detect agent role from description or type
if 'implement' in desc or agent_type == 'implementer':
    state['implementer_ran'] = True
elif 'review' in desc or agent_type == 'reviewer':
    state['reviewer_ran'] = True
elif 'test' in desc or agent_type == 'tester':
    state['tester_ran'] = True

json.dump(state, sys.stdout, indent=2)
" 2>/dev/null)

if [ -n "$UPDATED" ]; then
  echo "$UPDATED" > "$STATE_FILE"
fi

# Log to stderr (visible to user but doesn't block)
echo "AGENT SPAWN: [$AGENT_TYPE] $AGENT_DESC" >&2

exit 0
