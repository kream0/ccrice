---
description: Perform end-of-session documentation update before stopping
---

Perform the end-of-session wrap-up. This is MANDATORY before stopping.

## Step 1: Curate beliefs

Run `mem-reason curate` to clean up stale or low-confidence beliefs.

## Step 2: Save handoff

Summarize the session state and save it as a handoff belief. The handoff must capture what the next session needs to know.

Format: `STATE: <what was done>. NEXT: <what should happen next>. BLOCKERS: <any blockers or "none">.`

```bash
mem-reason handoff "STATE: <fill in>. NEXT: <fill in>. BLOCKERS: <fill in>."
```

## Step 3: Write session report

The stop-gate requires a fresh report file at `$HOME/fang/reports/<SESSION>.json`. Write it so the next stop is unblocked.

```bash
SESSION_NAME="${FANG_WINDOW_NAME:-proj-$(basename "$PWD")}"
mkdir -p "$HOME/fang/reports"
python3 -c "
import json, os, datetime, sys
report = {
    'project': os.path.basename(os.getcwd()),
    'session': sys.argv[1],
    'summary': sys.argv[2],
    'status': 'wrapped',
    'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
with open(os.path.expanduser(f'~/fang/reports/{sys.argv[1]}.json'), 'w') as f:
    json.dump(report, f, indent=2)
" "$SESSION_NAME" "<one-line summary of session>"
```

---

**IMPORTANT:** Do NOT create or update markdown tracking files (LAST_SESSION.md, TODO.md, COMPLETED_TASKS.md, BACKLOG.md). The mem-reason belief store is the sole persistence layer.

$ARGUMENTS
