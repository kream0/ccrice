---
description: End session — run deterministic session-end script
---

Run this command immediately — do NOT narrate or plan, just execute:

```
bash ./.claude/hooks/project-session-end.sh $ARGUMENTS
```

Read the output. If the script reports errors, fix them and re-run.

**Important:** This script saves beliefs via memr and commits .memorai/ — it must NOT create markdown tracking files (no LAST_SESSION.md, TODO.md, etc.). The belief store is the sole persistence layer.

After the script completes, output ONLY this:
```
Session closed. [paste the summary line from script output]
```

Do NOT add commentary. Do NOT describe what happened. The script output is the report.

$ARGUMENTS
