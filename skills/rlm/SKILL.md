---
name: rlm
description: Launch an RLM autonomous dev session that reads TODO.md and spawns sub-agents to complete tasks
allowed-tools: Bash, Read, Glob, Grep
---

# RLM - Autonomous Dev Tool

RLM spawns autonomous Claude Code sub-agents that sequentially implement TODO items in any project.

## Quick Start

```bash
# Run all pending TODO items in a project
rlm dev --project-dir /path/to/project --verbose

# Run specific tasks
rlm dev --project-dir /path/to/project --task "Add input validation to login form" --task "Write tests for auth module" --verbose

# With budget limit
rlm dev --project-dir /path/to/project --claude-budget 5.0 --verbose
```

## How It Works

1. Reads `CLAUDE.md` (project rules) and `TODO.md` (task list) from the project directory
2. Parses unchecked tasks (`- [ ] ...`) from TODO.md
3. For each task, spawns a `claude -p` sub-agent with `--permission-mode bypassPermissions`
4. Each sub-agent: reads code, makes changes, runs tests, checks off its TODO item
5. Results accumulate - later agents know what earlier ones did
6. Updates `LAST_SESSION.md` with a session report

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--project-dir <dir>` | Target project directory (required) | — |
| `--task "<task>"` | Explicit task (repeatable) | Parse from TODO.md |
| `--on-failure <mode>` | `continue`, `stop`, or `retry` | `continue` |
| `--claude-model <model>` | Model for sub-agents | `opus` |
| `--claude-budget <usd>` | Max budget per sub-agent | unlimited |
| `--verbose` | Enable verbose logging | off |

## TODO.md Format

RLM parses tasks in these formats:

```markdown
## Section Name

- [ ] **Bold Title** - Description of what to do
- [ ] Plain task without bold formatting
- [x] Already completed (skipped)
```

## Prerequisites

1. Build RLM: `cd /path/to/rlm && bun run build`
2. Link globally: `cd /path/to/rlm && bun link`
3. Ensure `claude` CLI is available in PATH

## Example Usage from Claude Code

When a user says "use RLM to continue development on project X":

```bash
rlm dev --project-dir /absolute/path/to/project-x --verbose
```

To monitor progress, watch stderr output. The session report is printed at the end and saved to `LAST_SESSION.md`.
