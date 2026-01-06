# Autonoma Installation

## Prerequisites

- [Bun](https://bun.sh) runtime
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/kream0/autonoma.git
   cd autonoma
   ```

2. Install dependencies:
   ```bash
   bun install
   ```

3. Run commands via:
   ```bash
   bun run dev <command>
   ```

## Quick Test

```bash
# Verify installation
bun run dev doctor

# Run demo mode
bun run dev demo
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `start <requirements.md>` | Start new orchestration |
| `resume <project-dir>` | Resume from checkpoint |
| `status <project-dir>` | Show current state |
| `guide <project-dir> "msg"` | Send guidance to CEO |
| `pause <project-dir>` | Pause orchestration |
| `doctor` | Verify system health |
| `demo` | Run demonstration |

## Optional: Global Install

To use `autonoma` command directly (instead of `bun run dev`):

```bash
bun link
```

Then you can use:
```bash
autonoma start requirements.md
autonoma status ./project
```
