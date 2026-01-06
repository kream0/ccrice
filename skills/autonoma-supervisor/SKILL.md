---
name: autonoma-supervisor
description: Monitor and control Autonoma runs with token-efficient patterns. Use when launching Autonoma, checking Autonoma status, supervising multi-agent development, or sending guidance to a running Autonoma instance.
allowed-tools: Read, Bash, Glob
---

# Autonoma Supervisor

Supervise Autonoma multi-agent development runs without flooding your context.

**First time setup?** See [INSTALL.md](INSTALL.md)

## Quick Commands

```bash
# Start Autonoma on a project (from autonoma repo directory)
bun run dev start /path/to/project/requirements.md --stdout --max-developers 3

# Check status (token-efficient)
cat /path/to/project/.autonoma/state.json

# Send guidance to CEO
bun run dev guide /path/to/project "Your message here"
```

## Token-Efficient Monitoring

### DO: Read state.json directly

```bash
cat /path/to/project/.autonoma/state.json
```

Returns ~200-400 bytes with phase, agent states, and task progress.

### DON'T: Stream or tail logs

```bash
# AVOID - floods context
tail -f /path/to/project/.autonoma/logs/*.log
cat /path/to/project/.autonoma/logs/*.log
```

### Polling Intervals

| Phase | Check Every |
|-------|-------------|
| PLANNING | 5 minutes |
| TASK-BREAKDOWN | 3 minutes |
| DEVELOPMENT | 5-10 minutes |
| TESTING | 5 minutes |
| REVIEW | 3 minutes |

## Status File Schema

```json
{
  "phase": "DEVELOPMENT",
  "iteration": 1,
  "agents": {
    "ceo": "idle",
    "staff": "idle",
    "developers": ["running", "running", "idle"],
    "qa": "idle"
  },
  "tasks": {
    "total": 12,
    "completed": 7,
    "running": 2,
    "pending": 3
  },
  "updatedAt": "2025-12-29T10:30:00Z"
}
```

**Phases:** `PLANNING`, `TASK-BREAKDOWN`, `DEVELOPMENT`, `TESTING`, `REVIEW`, `CEO-APPROVAL`, `COMPLETE`

**Agent states:** `idle`, `running`, `error`

## When to Send Guidance

Use sparingly. Good reasons:
- Reprioritize features mid-run
- Clarify ambiguous requirements
- Redirect after observing wrong approach

```bash
bun run dev guide ./project "Focus on the API first, skip frontend for now"
```

## Supervision Pattern

1. **Launch**: Start Autonoma with `--stdout` in background or separate terminal
2. **Wait**: Let it work for 5-10 minutes
3. **Check**: Read `state.json` to see progress
4. **Summarize**: Tell user the phase and progress (don't paste raw JSON)
5. **Guide**: Only intervene if direction change needed
6. **Repeat**: Check again in 5-10 minutes

## Context Budget

| Activity | Token Cost | Frequency |
|----------|-----------|-----------|
| Read state.json | ~100-200 | Every 5-10 min |
| Send guidance | ~50-100 | As needed |
| Read log tail (50 lines) | ~500-1000 | On errors only |

**Target:** Keep supervision under 2000 tokens per hour.

## Example Session

```bash
# Start (from autonoma directory)
bun run dev start ./myproject/requirements.md --stdout &

# After 5 min
cat ./myproject/.autonoma/state.json
# → Phase: PLANNING, CEO running

# After 15 min
cat ./myproject/.autonoma/state.json
# → Phase: DEVELOPMENT, 3/8 tasks complete

# User wants API prioritized
bun run dev guide ./myproject "Prioritize REST API over frontend"

# After 30 min
cat ./myproject/.autonoma/state.json
# → Phase: COMPLETE, 8/8 tasks done
```

## Handling Errors

If agent shows `error` or progress stalls for 15+ minutes:

1. Read last 50 lines of log: `tail -50 /path/.autonoma/logs/session-*.log`
2. Send guidance if recoverable
3. Report to user if intervention needed

## Key Principles

1. **Check periodically, not continuously** - Autonoma is autonomous
2. **Read state.json, not logs** - Much smaller, structured data
3. **Summarize for users** - Interpret status, don't paste JSON
4. **Guide sparingly** - Only when direction change is needed
5. **Stay within budget** - ~2000 tokens/hour for supervision
