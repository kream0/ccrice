---
description: Set up Memorai autonomous agent system (auto-detects project state)
---

Run the Memorai setup script to detect project state and install/upgrade all components.

## Run Setup

```bash
# Interactive (prompts for confirmation)
python3 /mnt/c/Users/Karim/Documents/work/_tools/AI/memorai/.claude/skills/memorai/scripts/setup.py .

# Auto-confirm (no prompts)
python3 /mnt/c/Users/Karim/Documents/work/_tools/AI/memorai/.claude/skills/memorai/scripts/setup.py --yes .

# With automatic bootstrap (extracts knowledge from git/docs)
python3 /mnt/c/Users/Karim/Documents/work/_tools/AI/memorai/.claude/skills/memorai/scripts/setup.py --yes --bootstrap .

# Dry run (show what would be done)
python3 /mnt/c/Users/Karim/Documents/work/_tools/AI/memorai/.claude/skills/memorai/scripts/setup.py --dry-run .
```

## Project States Detected

| State | Description | Actions |
|-------|-------------|---------|
| EMPTY | No files | Full install + templates |
| NEW_PROJECT | Has code, no CCSCM | Full install |
| CCSCM_BASIC | Has TODO/LAST_SESSION, no Memorai | Add Memorai + supervisor |
| CCSCM_V1 | Old Memorai (missing scripts) | Upgrade + supervisor |
| CCSCM_V2 | Full Memorai, no supervisor | Add supervisor only |
| FULL_AUTONOMOUS | Everything present | Check for updates |

## What Gets Installed

| Component | Count | Description |
|-----------|-------|-------------|
| Python scripts | 15 | Core Memorai + autonomous agent |
| Slash commands | 8 | /start, /end, /mem-*, /supervisor |
| Agent templates | 6 | memory_curator, implementer, tester, etc. |
| supervisor.py | 1 | Daemon for autonomous operation |
| Tracking files | 3 | TODO.md, LAST_SESSION.md, BACKLOG.md |
| CLAUDE.md | 1 | Full methodology + daemon protocol |
| Database | 1 | SQLite with memories, tasks, checkpoints |

## After Setup

The script will detect if you have git history or documentation and offer to run `/mem-bootstrap` to extract existing knowledge.

```bash
# Start interactive session
/start

# Start autonomous daemon
/supervisor
# or: python3 supervisor.py .
```
