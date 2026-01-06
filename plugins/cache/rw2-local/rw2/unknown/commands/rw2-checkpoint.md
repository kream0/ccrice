---
description: Resume or manage Ralph checkpoint pauses
---

Manage Ralph loop checkpoints. Use this command when the loop has paused for review.

Usage:
  /ralph-checkpoint continue  - Resume the loop after checkpoint review
  /ralph-checkpoint status    - Show checkpoint information

```bash
CHECKPOINT_FILE=".claude/RALPH_CHECKPOINT.md"
STATE_FILE=".claude/ralph-loop.local.md"

ACTION="${1:-status}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active Ralph loop."
  exit 1
fi

case "$ACTION" in
  continue|resume)
    if [[ -f "$CHECKPOINT_FILE" ]]; then
      rm "$CHECKPOINT_FILE"
      echo "Checkpoint cleared. Ralph will continue on next iteration."
    else
      echo "No checkpoint is currently active."
    fi
    ;;
  status)
    if [[ -f "$CHECKPOINT_FILE" ]]; then
      cat "$CHECKPOINT_FILE"
    else
      echo "No checkpoint is currently active."
      echo ""
      echo "Loop status:"
      head -15 "$STATE_FILE"
    fi
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo ""
    echo "Usage:"
    echo "  /ralph-checkpoint continue  - Resume the loop"
    echo "  /ralph-checkpoint status    - Show checkpoint info"
    ;;
esac
```

Arguments provided: $ARGUMENTS

Handle the checkpoint action based on arguments.
If "continue" or "resume", clear the checkpoint and confirm.
If "status" or no args, show checkpoint status.
