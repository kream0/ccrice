---
description: Query past Ralph sessions from memorai
---

Query past Ralph sessions, learnings, and error patterns from memorai.

**Usage:**
- `/ralph-recall` - Show recent Ralph sessions
- `/ralph-recall sessions` - List past session summaries
- `/ralph-recall errors` - List error patterns learned
- `/ralph-recall learnings` - List key learnings from past sessions
- `/ralph-recall stats` - Show Ralph statistics
- `/ralph-recall <query>` - Search for specific Ralph memories

**Advanced Options:**
- `--global` - Search across all known projects
- `--since <date>` - Filter by date (e.g., "7d", "1w", "1m", "2026-01-01")
- `--until <date>` - Filter until date
- `--compact` - Compact output format

**Examples:**
- `/ralph-recall typescript` - Find TypeScript-related learnings
- `/ralph-recall errors --since 7d` - Errors from last week
- `/ralph-recall --global sessions` - All sessions across projects
- `/ralph-recall stats --global` - Statistics from all projects

```bash
PLUGIN_ROOT="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
ARGS="$*"

# Parse arguments
MODE="sessions"
QUERY=""
GLOBAL="false"
SINCE=""
UNTIL=""
FORMAT="markdown"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      GLOBAL="true"
      shift
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --until)
      UNTIL="$2"
      shift 2
      ;;
    --compact)
      FORMAT="compact"
      shift
      ;;
    sessions|errors|learnings|stats)
      MODE="$1"
      shift
      ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
        MODE="search"
      else
        QUERY="$QUERY $1"
      fi
      shift
      ;;
  esac
done

# Check for memorai locally (unless using global search)
if [[ "$GLOBAL" != "true" ]]; then
  if [[ ! -d ".memorai" ]]; then
    echo "Memorai database not initialized locally."
    echo ""
    echo "Options:"
    echo "  - Run 'memorai init' to initialize in this project"
    echo "  - Use --global to search across all known projects"
    exit 1
  fi
fi

# Build JSON input
INPUT="{\"mode\":\"$MODE\""
if [[ -n "$QUERY" ]]; then
  INPUT="$INPUT,\"query\":\"$QUERY\""
fi
if [[ "$GLOBAL" == "true" ]]; then
  INPUT="$INPUT,\"global\":true"
fi
if [[ -n "$SINCE" ]]; then
  INPUT="$INPUT,\"since\":\"$SINCE\""
fi
if [[ -n "$UNTIL" ]]; then
  INPUT="$INPUT,\"until\":\"$UNTIL\""
fi
INPUT="$INPUT,\"format\":\"$FORMAT\",\"limit\":15}"

# Run the recall script
cd "$(pwd)"
RESULT=$(echo "$INPUT" | bun run "${PLUGIN_ROOT}/scripts/ralph-recall.ts" 2>&1)

# Output the formatted result (from stderr) or error
if echo "$RESULT" | grep -q '"success":true'; then
  # Extract the formatted output (everything after the JSON ends)
  echo "$RESULT" | sed -n '/^$/,$p' | tail -n +2
else
  echo "Error querying memorai:"
  echo "$RESULT"
fi
```

Arguments provided: $ARGUMENTS

Based on the arguments:
- If no arguments or "sessions": Show recent Ralph session summaries
- If "errors": Show error patterns that have been learned
- If "learnings": Show key learnings from past sessions
- If "stats": Show Ralph usage statistics
- Otherwise: Search for Ralph-related memories matching the query

Options:
- `--global`: Search across all memorai-enabled projects
- `--since <date>`: Filter results newer than date (supports "7d", "1w", "1m", "1y" or ISO dates)
- `--until <date>`: Filter results older than date
- `--compact`: Show compact single-line format

Display the results in a readable format showing:
- Title and relevance
- Category, date, and importance level
- Tags
- Project name (for global searches)
- Summary/content
