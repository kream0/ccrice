---
description: Send a one-time instruction to the Ralph loop
---

Send a one-time instruction that will be injected into the next iteration's context.

Usage: /ralph-nudge <instruction>

Example: /ralph-nudge Focus on the authentication module first

```bash
NUDGE_FILE=".claude/RALPH_NUDGE.md"
STATE_FILE=".claude/ralph-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active Ralph loop. Start one with /ralph-loop"
  exit 1
fi

# Get the instruction from arguments
INSTRUCTION="$*"

if [[ -z "$INSTRUCTION" ]]; then
  echo "Usage: /ralph-nudge <instruction>"
  echo ""
  echo "Example: /ralph-nudge Focus on the authentication module first"
  exit 1
fi

# Write the nudge file
echo "$INSTRUCTION" > "$NUDGE_FILE"

echo "Nudge queued for next iteration:"
echo "  $INSTRUCTION"
echo ""
echo "The instruction will be injected as a priority message in the next iteration."
```

Arguments provided: $ARGUMENTS

If no arguments were provided, show the usage instructions.
If arguments were provided, confirm the nudge was queued.
