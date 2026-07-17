#!/bin/bash
# Hook: PreToolUse[AskUserQuestion] (project agent)
# Purpose: Make the interactive deadlock STRUCTURALLY impossible.
#
# Autonomous agents run HEADLESS — there is no human at the TUI to answer an
# AskUserQuestion prompt, so calling it freezes the agent forever (see #94).
# This hook DENIES the AskUserQuestion tool and redirects the agent to the
# async owner-question bridge `fang-q`, whose answer is injected back into the
# session when the owner replies — no blocking wait.
#
# PreToolUse contract: read the tool-call JSON on stdin; exit 2 to DENY the call
# (the stderr message is shown to the agent); exit 0 to allow. This hook is a
# pure structural guard — it never blocks any other tool, so it cannot deadlock.

INPUT=$(cat 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
# Fallback parse if jq is unavailable / payload is malformed.
if [ -z "$TOOL" ]; then
  TOOL=$(printf '%s' "$INPUT" \
    | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')
fi

if [ "$TOOL" = "AskUserQuestion" ]; then
  echo "TOOL BLOCKED: AskUserQuestion is disabled for autonomous agents." >&2
  echo "You run HEADLESS — no one can answer an interactive prompt and it will DEADLOCK you." >&2
  echo "" >&2
  echo "Ask the owner via the ASYNC bridge instead:" >&2
  echo "  ~/fang/display/fang-q ask \"<your question>\" --kind {mcq|freetext|approval|spec_approval} [--options \"A,B,C\"]" >&2
  echo "" >&2
  echo "The owner's answer is injected back into your session when it arrives." >&2
  echo "After asking, keep doing other non-blocked work. If EVERYTHING left is" >&2
  echo "owner-gated: send the question via fang-q, THEN 'rm .roadmap-active' to idle cleanly." >&2
  exit 2
fi

# Not AskUserQuestion (defensive — the matcher should scope this) → allow.
exit 0
