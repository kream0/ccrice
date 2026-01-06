---
description: Start the Memorai supervisor daemon for autonomous operation
---

Start the supervisor daemon to enable autonomous agent operation. The daemon will:
- Spawn and manage Claude instances
- Monitor context usage and trigger checkpoints
- Inject human messages from the queue
- Auto-respawn on exit/crash

## Check Prerequisites

First verify the project is set up:

```bash
python3 .claude/skills/memorai/scripts/setup.py --dry-run .
```

If not fully set up, run `/mem-setup` first.

## Start Supervisor

Choose a model and start:

```bash
# Default (opus) - most capable
python3 supervisor.py .

# Sonnet - balanced
python3 supervisor.py --model sonnet .

# Haiku - fastest/cheapest
python3 supervisor.py --model haiku .

# With debug logging
python3 supervisor.py --debug .
```

## Load Tasks (Optional)

If you have a PRD, parse it into the task queue first:

```bash
python3 .claude/skills/memorai/scripts/prd_parser.py parse docs/PRD.md --queue
```

Or add tasks manually:

```bash
python3 .claude/skills/memorai/scripts/tasks.py add --title "Task name" --description "Details" --priority 7
```

## Monitor & Control

While supervisor is running (in another terminal):

```bash
# Send steering message
python3 .claude/skills/memorai/scripts/human_queue.py steer "Focus on X first"

# Send high-priority override
python3 .claude/skills/memorai/scripts/human_queue.py override "Stop and checkpoint"

# Ask a blocking question
python3 .claude/skills/memorai/scripts/human_queue.py ask "Should I use approach A or B?"

# List pending messages
python3 .claude/skills/memorai/scripts/human_queue.py list

# Check task queue
python3 .claude/skills/memorai/scripts/tasks.py summary
```

## Stop Supervisor

Press Ctrl+C to gracefully stop. The daemon will:
1. Request checkpoint from Claude
2. Wait for state to be saved
3. Exit cleanly

---

**Note:** The supervisor runs in the foreground. For background operation, use:
```bash
nohup python3 supervisor.py . > supervisor.log 2>&1 &
```
