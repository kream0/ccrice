# ccrice

Claude Code "Ricing" - personal configuration, commands, skills, hooks, and plugins for [Claude Code](https://claude.ai/code).

## What is this?

This repo stores portable Claude Code customizations that can be symlinked to `~/.claude/` on any machine. Think of it as dotfiles, but for Claude Code.

## Structure

```
ccrice/
├── commands/          # Slash commands (*.md)
├── hooks/             # Event hooks (JS scripts)
├── plugins/           # Installed plugins and marketplace config
├── skills/            # Complex skills with dependencies
└── settings.json      # Base settings template
```

## Installation

Clone and symlink to your Claude Code config directory:

```bash
git clone https://github.com/kream0/ccrice.git ~/ccrice

# Symlink individual commands
ln -sf ~/ccrice/commands/*.md ~/.claude/commands/

# Or symlink the entire directory (careful with existing files)
ln -sf ~/ccrice/commands ~/.claude/commands
```

## Commands

| Command | Description |
|---------|-------------|
| `/start` | Initialize session context by reading tracking files |
| `/end` | End-of-session documentation update |
| `/stack` | Quick verification of development servers |
| `/test` | Pre-test checklist before running tests |
| `/pr-review` | PR review with optional reference branch for pattern compliance |
| `/mem-setup` | Set up Memorai autonomous agent system |
| `/mem-bootstrap` | Scan project and extract knowledge into Memorai |
| `/supervisor` | Start the Memorai supervisor daemon |

### `/pr-review` Usage

Standard PR review:
```
/pr-review feature-branch main
```

With reference branch for architectural pattern compliance:
```
/pr-review feature-branch main --ref gold-standard-branch
```

## Skills

| Skill | Description |
|-------|-------------|
| `browser-lite` | Token-efficient browser debugging via Chrome DevTools |
| `android-driver` | Android device control for mobile app testing |
| `autonoma-supervisor` | Monitor and control Autonoma multi-agent runs |

## Hooks

- **leash_hook.js** - Remote monitoring integration for mobile notifications

## Making Commands Global

Commands in `~/.claude/commands/` are available in all projects. Symlink from this repo:

```bash
ln -sf ~/ccrice/commands/pr-review.md ~/.claude/commands/
```

## Portability

The repo is designed to be machine-agnostic:
- Paths use `~` expansion
- Sensitive files are gitignored (`.credentials.json`, `settings.local.json`)
- Cache and generated directories are excluded
