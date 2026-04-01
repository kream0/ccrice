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

## Step 3: End session

```bash
mem-reason session-end --summary "<one-line summary of session>"
```

## Step 3b: Rotation stamp

If `$ARGUMENTS` contains `--rotate`, touch the rotation stamp so the stop gate allows through:

```bash
touch /tmp/fang-rotating
```

## Step 4: Commit belief store

```bash
cd /home/karimel/ccrice && git add -A .memorai/ && git commit -m "chore: session end $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null || true
```

---

**IMPORTANT:** Do NOT create or update markdown tracking files (LAST_SESSION.md, TODO.md, COMPLETED_TASKS.md, BACKLOG.md). The mem-reason belief store is the sole persistence layer.

$ARGUMENTS
