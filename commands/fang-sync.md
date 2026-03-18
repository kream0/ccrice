---
description: Sync fang config to fang repo and memory to ccrice. Usage: /fang-sync [--config-only | --memory-only]
---

Run `~/fang/display/fang-sync` to sync config and memory to their respective repos.

- **Config** (projects.json, watchers.json, CLAUDE.md) → `~/fang-src/` (github.com/kream0/fang)
- **Memory** (master.sql) → `~/ccrice/` (github.com/kream0/ccrice)

```bash
~/fang/display/fang-sync                # sync both
~/fang/display/fang-sync --config-only  # config only
~/fang/display/fang-sync --memory-only  # memory only
```

**NEVER manually copy files and run git commands for sync.** Always use this script. It handles pull, diff, commit, push, and skips if already in sync.
