---
description: End session — run deterministic session-end script
---

Run this command immediately — do NOT narrate or plan, just execute:

```
bash ./.claude/hooks/project-session-end.sh
```

Read the output. If the script reports errors, fix them and re-run.

If the user provided a session summary via $ARGUMENTS, pass it:
```
bash ./.claude/hooks/project-session-end.sh "$ARGUMENTS"
```

After the script completes, output ONLY this:
```
Session closed. [paste the summary line from script output]
```

Do NOT add commentary. Do NOT describe what happened. The script output is the report.

$ARGUMENTS
