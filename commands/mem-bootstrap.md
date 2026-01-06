---
description: Scan project and extract knowledge into Memorai (2-phase approach)
---

Bootstrap Memorai with knowledge from the existing codebase. Uses a lightweight 2-phase approach to avoid context overload.

## Phase 1: Scan (Lightweight ~2k tokens)

Get a project overview without loading everything:

```bash
python3 .claude/skills/memorai/scripts/bootstrap.py scan --days 30
```

**Output includes:**
- **Structure**: Directories, file types, key entry points
- **Patterns**: Framework, language, testing stack detected
- **Documentation**: List of docs with titles (not content)
- **Recent activity**: Last N days of commits (subjects only)
- **Tracking history**: Changes to TODO.md, LAST_SESSION.md, CLAUDE.md
- **Recommendations**: What to extract next

## Phase 2: Extract (On Demand)

Based on the scan, extract only what's relevant:

```bash
# Get documentation content (CLAUDE.md, README, etc.)
python3 .claude/skills/memorai/scripts/bootstrap.py extract docs

# Get recent commits with full messages
python3 .claude/skills/memorai/scripts/bootstrap.py extract commits --days 7

# Get detailed codebase structure
python3 .claude/skills/memorai/scripts/bootstrap.py extract structure

# Get tracking files history and current content
python3 .claude/skills/memorai/scripts/bootstrap.py extract tracking
```

## What to Store in Memorai

After reviewing, store important findings:

| What to Store | Category | Importance |
|---------------|----------|------------|
| Architecture decisions (why X over Y) | `architecture` | 8-10 |
| Tech stack choices with rationale | `decisions` | 7-8 |
| Key patterns/conventions | `architecture` | 7-8 |
| Integration gotchas | `notes` | 8 |
| Project structure overview | `structure` | 6-7 |

**Skip:** Pure implementation details, outdated info, trivial TODOs.

## Example Workflow

```bash
# 1. Quick scan (lightweight)
python3 .claude/skills/memorai/scripts/bootstrap.py scan --days 30

# 2. Based on scan, extract relevant docs
python3 .claude/skills/memorai/scripts/bootstrap.py extract docs

# 3. Look at recent work for context
python3 .claude/skills/memorai/scripts/bootstrap.py extract commits --days 7

# 4. Store key findings
python3 .claude/skills/memorai/scripts/store.py \
  -c architecture \
  -t "Project Architecture - Angular + Supabase + Express" \
  --content "Frontend: Angular 18 with standalone components...
Backend: Express.js API with Supabase database...
Why this stack: ..." \
  --importance 8 \
  --tags "architecture,bootstrap"
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--days N` | 30 | Days of git history to scan |
| `--limit N` | 50 | Max commits to extract |

## Why 2-Phase?

| Old Approach | New Approach |
|--------------|--------------|
| Load 449 commits at once | Scan last 30 days only |
| ~50k tokens minimum | ~2k tokens for scan |
| Context overload risk | Agent decides what to extract |
| No structure awareness | Detects patterns, key files |
