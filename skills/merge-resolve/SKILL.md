---
name: merge-resolve
description: Resolve git merge conflicts with deterministic one-action scripts. Use when files contain conflict markers (<<<<<<< / ======= / >>>>>>>).
allowed-tools: Bash(merge-resolve:*)
---

# Merge Conflict Resolution

Resolve conflicts using indexed, one-shot commands instead of complex search/replace on conflict markers.

## Workflow

1. **List** conflicted files: `merge-resolve.sh list`
2. **Show** conflicts numbered: `merge-resolve.sh show <file>`
3. **Resolve** each by number: `merge-resolve.sh ours|theirs|both <file> [N]`
4. **Repeat** until no conflicts remain, then `git add <file>`

## Commands

```
merge-resolve.sh list                       # list files with conflicts
merge-resolve.sh show   <file> [N]         # show conflict N (or all), numbered
merge-resolve.sh ours   <file> [N]         # keep HEAD side for conflict N (or all)
merge-resolve.sh theirs <file> [N]         # keep incoming side for conflict N (or all)
merge-resolve.sh both   <file> [N]         # concatenate both sides for conflict N (or all)
merge-resolve.sh batch  <file> o,t,b,...   # resolve all at once with per-conflict decisions
```

Omit `N` to resolve all conflicts in the file at once.

## Batch Mode

Resolve every conflict in one command. Pass a comma-separated string of decisions:
- `o` = ours, `t` = theirs, `b` = both, `s` = skip

```
merge-resolve.sh batch file.tsx "o,t,b,o"
```

Use `show` first, then `batch` — fastest path: two commands, done.

## Tips

- After resolving, re-run `show` to verify. Conflict indices shift after resolution.
- Handles both standard and diff3 (`|||||||`) conflict formats.
