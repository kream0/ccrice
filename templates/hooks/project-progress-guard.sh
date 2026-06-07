#!/bin/bash
# Hook: PreToolUse[Bash] (project agent)
# Purpose: Force every MILESTONE through the evidence-gated `fang-milestone`
# tool by DENYING raw Bash appends/writes to ~/fang/progress/<project>.txt.
#
# The heartbeat relay only forwards strict-format MILESTONE lines to the owner,
# and `fang-milestone` is the ONLY sanctioned writer — it validates reviewer +
# fresh screenshot + health sha before appending (see #73/#94). A raw
# `echo ... >> ~/fang/progress/foo.txt` bypasses every check and fakes a
# milestone. This guard blocks that; the fang-milestone tool itself is
# allowlisted so the sanctioned path is never impeded.
#
# PreToolUse contract: read the tool-call JSON on stdin; exit 2 to DENY (stderr
# shown to the agent); exit 0 to allow. Only Bash commands that target the
# progress file via a redirect / tee / write are denied — everything else
# (including reads of the file) passes. It never blocks fang-milestone, so it
# cannot deadlock the autonomous loop.

INPUT=$(cat 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
if [ -z "$TOOL" ]; then
  TOOL=$(printf '%s' "$INPUT" \
    | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
fi

# Only inspect Bash tool calls.
[ "$TOOL" = "Bash" ] || exit 0
[ -n "$CMD" ] || exit 0

# Allowlist: the sanctioned milestone writer. If the command invokes
# fang-milestone, let it through untouched (it does its own evidence gate +
# append). Match it as a token so a stray substring elsewhere can't fake it.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]/])fang-milestone([[:space:]]|$)'; then
  exit 0
fi

# Does the command reference the progress store at all?  Match both the literal
# ~/fang/progress/ form and an expanded $HOME/.../fang/progress/ path.
if ! printf '%s' "$CMD" | grep -qE '(~|\$HOME|/[^[:space:]]*)?/?fang/progress/'; then
  exit 0
fi

# It touches fang/progress/ — deny only WRITE/APPEND intents, not reads.
#   - redirection:   > … / >> …  pointing at the progress path
#   - tee:           tee [-a] … progress path
#   - in-place edit: sed -i … / install / cp / mv / dd / truncate onto the path
#   - editors/printf piped into the path
WRITE=0
# Redirection (>, >>) anywhere before/after the path, possibly with fd numbers.
if printf '%s' "$CMD" | grep -qE '>>?[[:space:]]*("?)(~|\$HOME|/)[^[:space:]"|;&]*fang/progress/'; then
  WRITE=1
fi
# tee writing to the progress path.
if printf '%s' "$CMD" | grep -qE '\btee\b([[:space:]]+-[a-zA-Z]+)*[[:space:]]+("?)(~|\$HOME|/)[^[:space:]"|;&]*fang/progress/'; then
  WRITE=1
fi
# Mutating utilities targeting the progress path.
if printf '%s' "$CMD" | grep -qE '\b(sed[[:space:]]+-i|cp|mv|dd|truncate|install|ed|ex)\b[^|;&]*fang/progress/'; then
  WRITE=1
fi

if [ "$WRITE" -eq 1 ]; then
  echo "TOOL BLOCKED: raw writes/appends to ~/fang/progress/<project>.txt are not allowed." >&2
  echo "MILESTONEs MUST go through the evidence-gated tool so the owner only sees verified progress:" >&2
  echo "  ~/fang/display/fang-milestone <project> \"<text>\" --reviewer <agent-id> \\" >&2
  echo "      --screenshot <fresh.png> --health <short-sha> [--health-url <url>]" >&2
  echo "" >&2
  echo "It validates the reviewer, a fresh e2e screenshot, and the commit sha before appending." >&2
  echo "Reading the progress file is fine; only raw appends/writes are blocked." >&2
  exit 2
fi

exit 0
