# Ralph Wiggum Plugin (v2)

> **Based on:** [ralph-wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum) from the official Claude Code plugins repository by Anthropic.

Enhanced implementation of the Ralph Wiggum technique for iterative, self-referential AI development loops in Claude Code.

## What is Ralph?

Ralph is a development methodology based on continuous AI agent loops. As Geoffrey Huntley describes it: **"Ralph is a Bash loop"** - a simple `while true` that repeatedly feeds an AI agent a prompt file, allowing it to iteratively improve its work until completion.

The technique is named after Ralph Wiggum from The Simpsons, embodying the philosophy of persistent iteration despite setbacks.

## v2 Enhancements

This version implements **deliberate malloc and context management** - the key insight from the original technique that was missing from earlier implementations:

### Context Management
- **Memorai Integration** - All session memory stored in SQLite (cross-session learning)
- **RALPH_STATUS.md** - Real-time dashboard for monitoring
- **Goal recitation** - Each iteration receives formatted context with mission, status, and next actions

### Adaptive Strategies
Automatic strategy switching based on iteration and error patterns:
- **Explore** (1-10): Try different approaches broadly
- **Focused** (11-35): Commit to best approach
- **Cleanup** (36+): Finish incomplete work
- **Recovery**: Triggered by 3+ repeated errors

### HOTL Monitoring (Human On The Loop)
- Checkpoints for periodic review
- Nudge system for one-time instructions
- Desktop notifications (optional)
- Status dashboard with error tracking

### Memorai Integration (Required)
Ralph v2 uses [Memorai](https://github.com/kream0/memorai) as its sole memory backend:
- **Session persistence** - Objectives, state, progress, and learnings stored to SQLite
- **Context injection** - Past learnings automatically included in context
- **Cross-project search** - Query Ralph memories across all projects with `/ralph-recall --global`
- **Date filtering** - Search by time range (e.g., `--since 7d`, `--until 2026-01-01`)

### Core Concept

This plugin implements Ralph using a **Stop hook** that intercepts Claude's exit attempts:

```bash
# You run ONCE:
/ralph-loop "Your task description" --completion-promise "DONE" --checkpoint 10

# Then Claude Code automatically:
# 1. Works on the task
# 2. Tries to exit
# 3. Stop hook analyzes transcript
# 4. Updates memory and status
# 5. Determines strategy
# 6. Builds enhanced context with goal recitation
# 7. Feeds context back as prompt
# 8. Repeat until completion or max iterations
```

## Quick Start

```bash
/ralph-loop "Build a REST API for todos. Requirements: CRUD operations, input validation, tests. Output <promise>COMPLETE</promise> when done." --completion-promise "COMPLETE" --max-iterations 50 --checkpoint 10
```

Monitor progress:
```bash
/ralph-status
```

Send guidance if needed:
```bash
/ralph-nudge "Focus on the authentication middleware first"
```

## Commands

### /ralph-loop

Start a Ralph loop in your current session.

**Usage:**
```bash
/ralph-loop "<prompt>" [OPTIONS]
```

**Options:**
| Option | Description |
|--------|-------------|
| `--max-iterations <n>` | Stop after N iterations (default: unlimited) |
| `--completion-promise <text>` | Phrase that signals completion |
| `--checkpoint <n>` | Pause for review every N iterations |
| `--checkpoint-mode <pause\|notify>` | "pause" stops for input, "notify" just alerts |

### /cancel-ralph

Cancel the active Ralph loop.

### /ralph-status

View the real-time status dashboard.

### /ralph-nudge <instruction>

Send a one-time instruction to the loop. Injected in next iteration then removed.

### /ralph-checkpoint <action>

Manage checkpoint pauses:
- `status` - View checkpoint info
- `continue` - Resume after checkpoint

### /ralph-recall [mode] [OPTIONS]

Query past Ralph sessions from Memorai.

**Modes:**
- `sessions` - Past session summaries (default)
- `errors` - Error patterns learned
- `learnings` - Key learnings
- `stats` - Usage statistics
- `<query>` - Custom search

**Options:**
| Option | Description |
|--------|-------------|
| `--global` | Search across all known projects |
| `--since <date>` | Filter by date (e.g., "7d", "1w", "1m") |
| `--until <date>` | Filter until date |
| `--compact` | Compact output format |

**Examples:**
```bash
/ralph-recall --global sessions        # All sessions across projects
/ralph-recall errors --since 7d        # Recent errors
/ralph-recall stats --global           # Global statistics
```

## Context Files

| File | Purpose |
|------|---------|
| `.claude/ralph-loop.local.md` | Active loop state (YAML frontmatter + prompt) |
| `.claude/RALPH_STATUS.md` | Real-time dashboard |
| `.claude/RALPH_NUDGE.md` | One-time instruction (injected then deleted) |
| `.claude/RALPH_SUMMARY.md` | Post-loop summary |
| `.memorai/memory.db` | Session memory (SQLite via Memorai) |

## Technical Architecture

```
hooks/
  stop-hook.sh          # Main loop logic (integrates TS scripts)
  precompact-hook.sh    # Preserves goals before /compact
  session-resume-hook.sh # Reinjects context on resume
  notification-hook.sh  # Desktop notifications
  hooks.json            # Hook registrations

scripts/
  analyze-transcript.ts # Parse errors, progress, phases (stores to memorai)
  strategy-engine.ts    # Determine adaptive strategy
  update-memory.ts      # Store session state to memorai
  update-status.ts      # Update RALPH_STATUS.md dashboard
  build-context.ts      # Build prompt with goal recitation + memorai queries
  generate-summary.ts   # Create post-loop analysis + store to memorai
  ralph-recall.ts       # Query past sessions (global search, date filters)
  run-headless.sh       # Headless/AFK operation wrapper
  types.ts              # TypeScript type definitions

commands/
  ralph-loop.md         # Start command
  cancel-ralph.md       # Cancel command
  ralph-status.md       # Status command
  ralph-nudge.md        # Nudge command
  ralph-checkpoint.md   # Checkpoint command
  ralph-recall.md       # Query past sessions command
  help.md               # Help docs
```

## Prompt Writing Best Practices

### 1. Clear Completion Criteria

```markdown
Build a REST API for todos.

When complete:
- All CRUD endpoints working
- Input validation in place
- Tests passing (coverage > 80%)
- README with API docs
- Output: <promise>COMPLETE</promise>
```

### 2. Incremental Goals

```markdown
Phase 1: User authentication (JWT, tests)
Phase 2: Product catalog (list/search, tests)
Phase 3: Shopping cart (add/remove, tests)

Output <promise>COMPLETE</promise> when all phases done.
```

### 3. Self-Correction

```markdown
Implement feature X following TDD:
1. Write failing tests
2. Implement feature
3. Run tests
4. If any fail, debug and fix
5. Refactor if needed
6. Repeat until all green
7. Output: <promise>COMPLETE</promise>
```

### 4. Escape Hatches

Always use `--max-iterations` as a safety net:

```bash
/ralph-loop "Try to implement feature X" --max-iterations 20 --checkpoint 10
```

## Philosophy

### 1. Iteration > Perfection
Don't aim for perfect on first try. Let the loop refine the work.

### 2. Failures Are Data
"Deterministically bad" means failures are predictable and informative.

### 3. Operator Skill Matters
Success depends on writing good prompts, not just having a good model.

### 4. Context is King (v2)
"Deliberate malloc" - carefully manage what context is provided to maintain focus.

## When to Use Ralph

**Good for:**
- Well-defined tasks with clear success criteria
- Tasks requiring iteration and refinement
- Greenfield projects where you can walk away
- Tasks with automatic verification (tests, linters)

**Not good for:**
- Tasks requiring human judgment mid-loop
- One-shot operations
- Tasks with unclear success criteria
- Production debugging

## Requirements

- **Bun runtime** (for TypeScript scripts)
- **jq** (for JSON parsing in bash)
- **Claude Code** with plugin support
- **[Memorai](https://github.com/kream0/memorai)** (v1.0+) - Required for session memory
  ```bash
  bun add -g memorai
  memorai init  # Run in project root before starting ralph-loop
  ```

## Learn More

- Original technique: https://ghuntley.com/ralph/
- Ralph Orchestrator: https://github.com/mikeyobrien/ralph-orchestrator

## For Help

Run `/help` in Claude Code for detailed command reference and examples.
