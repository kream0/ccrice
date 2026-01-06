---
description: "Explain Ralph Wiggum technique and available commands"
---

# Ralph Wiggum Plugin Help (v2)

Please explain the following to the user:

## What is the Ralph Wiggum Technique?

The Ralph Wiggum technique is an iterative development methodology based on continuous AI loops, pioneered by Geoffrey Huntley.

**Core concept:**
```bash
while :; do
  cat PROMPT.md | claude-code --continue
done
```

The same prompt is fed to Claude repeatedly. The "self-referential" aspect comes from Claude seeing its own previous work in the files and git history, not from feeding output back as input.

**Each iteration:**
1. Claude receives the SAME prompt
2. Works on the task, modifying files
3. Tries to exit
4. Stop hook intercepts and feeds the same prompt again
5. Claude sees its previous work in the files
6. Iteratively improves until completion

The technique is described as "deterministically bad in an undeterministic world" - failures are predictable, enabling systematic improvement through prompt tuning.

## v2 Enhancements: Context Management

The enhanced plugin implements **deliberate malloc** - careful management of context across iterations:

### Memorai Integration
All session memory is stored in SQLite via memorai:
- Original objective (never changes)
- Current status
- Accomplished items
- Failed attempts
- Next actions
- Key learnings
- Cross-session search with `/ralph-recall`

### RALPH_STATUS.md
Real-time dashboard showing:
- Current iteration and phase
- Recent activity
- Error patterns
- Files changed

### Adaptive Strategies
The loop automatically adjusts its approach:
- **Explore** (iterations 1-10): Try different approaches
- **Focused** (iterations 11-35): Commit to best approach
- **Cleanup** (iterations 36+): Finish incomplete work
- **Recovery**: Triggered by repeated errors

### Goal Recitation
Each iteration receives a formatted context block with:
- Original mission
- Current status from memory
- Next actions
- Strategy guidance
- Key learnings (to avoid repeating mistakes)

---

## Available Commands

### /rw2:rw2-loop <PROMPT> [OPTIONS]

Start a Ralph loop in your current session.

**Usage:**
```
/rw2:rw2-loop "Refactor the cache layer" --max-iterations 20
/rw2:rw2-loop "Add tests" --completion-promise "TESTS COMPLETE"
/rw2:rw2-loop "Build auth" --checkpoint 10 --max-iterations 50
```

**Options:**
- `--max-iterations <n>` - Max iterations before auto-stop
- `--completion-promise <text>` - Promise phrase to signal completion
- `--checkpoint <n>` - Pause for review every N iterations
- `--checkpoint-mode <pause|notify>` - Checkpoint behavior

**How it works:**
1. Creates state file and initializes memory
2. You work on the task
3. When you try to exit, stop hook intercepts
4. Analyzes transcript for errors and progress
5. Updates memory and status dashboard
6. Determines strategy based on iteration/errors
7. Builds enhanced context with goal recitation
8. Continues until promise detected or max iterations

---

### /rw2:rw2-cancel

Cancel an active Ralph loop.

**Usage:**
```
/rw2:rw2-cancel
```

---

### /rw2:rw2-status

View the status dashboard.

**Usage:**
```
/rw2:rw2-status
```

Shows iteration, phase, recent activity, errors, and files changed.

---

### /rw2:rw2-nudge <instruction>

Send a one-time instruction to the loop.

**Usage:**
```
/rw2:rw2-nudge "Focus on the authentication module first"
/rw2:rw2-nudge "Skip the tests for now, prioritize core functionality"
```

The instruction is injected as a priority message in the next iteration, then removed.

---

### /rw2:rw2-checkpoint <action>

Manage checkpoint pauses.

**Usage:**
```
/rw2:rw2-checkpoint status    # View checkpoint info
/rw2:rw2-checkpoint continue  # Resume after checkpoint
```

---

### /rw2:rw2-recall [mode|query] [OPTIONS]

Query past Ralph sessions from memorai.

**Usage:**
```
/rw2:rw2-recall              # Recent sessions
/rw2:rw2-recall sessions     # Past session summaries
/rw2:rw2-recall errors       # Error patterns learned
/rw2:rw2-recall learnings    # Key learnings
/rw2:rw2-recall stats        # Usage statistics
/rw2:rw2-recall typescript   # Search for specific memories
```

**Options:**
```
--global                   # Search all known projects
--since 7d                 # Filter by date (7d, 1w, 1m, 1y)
--until 2026-01-01         # Filter until date
--compact                  # Compact output format
```

**Examples:**
```
/rw2:rw2-recall --global sessions          # All sessions across projects
/rw2:rw2-recall errors --since 7d          # Recent errors
/rw2:rw2-recall stats --global             # Global statistics
```

Searches memorai for Ralph-related memories including session summaries, error patterns, and key learnings from past runs.

**Requires:** Memorai database (`memorai init`) or `--global` flag

---

### /rw2:rw2-resume

Resume a previous Ralph session.

**Usage:**
```
/rw2:rw2-resume
```

---

## Key Concepts

### Completion Promises

To signal completion, Claude must output a `<promise>` tag:

```
<promise>TASK COMPLETE</promise>
```

The stop hook looks for this specific tag. Without it (or `--max-iterations`), Ralph runs infinitely.

### Context Files

| File | Purpose |
|------|---------|
| `.claude/ralph-loop.local.md` | Active loop state (iteration, config) |
| `.claude/RALPH_STATUS.md` | Real-time dashboard |
| `.claude/RALPH_NUDGE.md` | One-time instruction (auto-deleted) |
| `.claude/RALPH_SUMMARY.md` | Post-loop summary |
| `.memorai/memory.db` | Session memory (SQLite via Memorai) |

### Self-Reference Mechanism

The "loop" doesn't mean Claude talks to itself. It means:
- Same prompt repeated
- Claude's work persists in files
- Each iteration sees previous attempts
- Memorai tracks progress across /compact and sessions

## Example

### Interactive Bug Fix with Monitoring

```
/rw2:rw2-loop "Fix the token refresh logic in auth.ts. Output <promise>FIXED</promise> when all tests pass." --completion-promise "FIXED" --max-iterations 20 --checkpoint 5
```

Monitor progress:
```
/rw2:rw2-status
```

Send guidance if stuck:
```
/rw2:rw2-nudge "Try using the refresh token stored in localStorage"
```

## When to Use Ralph

**Good for:**
- Well-defined tasks with clear success criteria
- Tasks requiring iteration and refinement
- Iterative development with self-correction
- Greenfield projects

**Not good for:**
- Tasks requiring human judgment or design decisions
- One-shot operations
- Tasks with unclear success criteria
- Debugging production issues (use targeted debugging instead)

## Learn More

- Original technique: https://ghuntley.com/ralph/
- Ralph Orchestrator: https://github.com/mikeyobrien/ralph-orchestrator
