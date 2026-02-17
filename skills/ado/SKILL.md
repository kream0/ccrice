---
name: ado
description: >-
  Use this skill when the user asks about Azure DevOps work items (tasks, bugs,
  user stories), pull requests, PR comments, or needs to create PRs or reply to
  PR comments. Trigger phrases: "work item", "pull request", "PR", "Azure DevOps",
  "ADO", "DevOps board", "list PRs", "create PR", "PR comments", "review comments".
allowed-tools: Bash, Read
---

# Azure DevOps REST API

Interact with Azure DevOps: query work items, list/create/inspect PRs, read and
reply to PR comments.

## Script location

The backing script is co-located with this skill:

```
~/.claude/skills/ado/scripts/ado-api.sh
```

Resolve the absolute path at runtime:

```bash
# Works in both WSL and PowerShell (Git Bash / WSL-backed bash)
SCRIPT="$(dirname "$(readlink -f ~/.claude/skills/ado/SKILL.md)" 2>/dev/null || echo "$HOME/.claude/skills/ado")/scripts/ado-api.sh"
bash "$SCRIPT" <command> [args...]
```

Or simply:

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh <command> [args...]
```

## Configuration

The script reads `~/.claude/skills/ado/scripts/.ado-config` (or the file
pointed to by `ADO_CONFIG_FILE`). Required variables:

| Variable      | Description              |
|---------------|--------------------------|
| `ADO_PAT`     | Personal Access Token    |
| `ADO_ORG`     | Organization name        |
| `ADO_PROJECT` | Project name             |

Optional: `ADO_API_VER` (default `7.0`).

## CRITICAL — `--repo` is always required

There is **no default repository**. Every PR command **must** include
`--repo <repository-name>`. Infer the repo from conversation context
(the git remote, a repo the user mentioned, the project they are working in).
If you cannot determine the repo, **ask the user**.

## Available commands

### Fetch a single work item

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh work-item <id>
```

### Query work items by type

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh work-items <Task|Bug|"User Story"> [--state <state>] [--top N]
```

- `<type>` — one of `Task`, `Bug`, `User Story` (quote "User Story")
- `--state` — e.g. `Active`, `Closed`, `New`
- `--top` — max results (default 50)

### List pull requests

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh prs --repo <name> [--status <active|completed|abandoned|all>] [--top N] [--creator <id>]
```

### Fetch a single PR

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh pr-get <pr-id> --repo <name>
```

### Create a pull request

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh pr-create \
  --repo <name> \
  --source <branch> \
  --target <branch> \
  --title "PR title" \
  [--description "Details"] \
  [--reviewers "id1,id2"] \
  [--draft]
```

Branch names are auto-prefixed with `refs/heads/` if not already qualified.

### List PR comment threads

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh pr-comments <pr-id> --repo <name>
```

### Reply to a PR comment thread

```bash
bash ~/.claude/skills/ado/scripts/ado-api.sh pr-reply <pr-id> <thread-id> "Reply content" --repo <name>
```

## Agent guidelines

1. **Always pass `--repo`** — never omit it. Determine the repository from:
   - The current git remote (`git remote get-url origin` and parse the repo name)
   - A repo the user has mentioned in the conversation
   - Ask the user if ambiguous
2. **Quote multi-word values** — e.g. `"User Story"`, PR titles, descriptions.
3. **Parse JSON output** — the script returns raw JSON (pretty-printed if `jq`
   is installed). Extract and summarize the relevant fields for the user rather
   than dumping raw JSON.
4. **Thread IDs for replies** — when replying to a PR comment, first fetch
   threads with `pr-comments`, identify the correct `threadId`, then use
   `pr-reply`.
5. **Error handling** — if the script returns an error, read the message and
   explain the issue to the user (expired PAT, wrong repo name, etc.).
