---
description: View the Ralph loop status dashboard
---

Display the current Ralph loop status dashboard.

```bash
if [[ -f ".claude/RALPH_STATUS.md" ]]; then
  cat .claude/RALPH_STATUS.md
else
  echo "No active Ralph loop. Start one with /ralph-loop"
fi
```

If a Ralph loop is active, show me the status dashboard above.
If not active, let me know.
