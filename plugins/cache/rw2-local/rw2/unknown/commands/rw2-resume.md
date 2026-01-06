# Ralph Resume

Resume a Ralph loop after a cycle restart. This command loads the most recent handoff
from Memorai and continues working on the original objective with fresh context.

## When to Use

After seeing `<ralph-cycle-restart/>` in the output, run this command to continue
the task with a fresh context window while preserving all progress.

## How It Works

1. Queries Memorai for the most recent cycle handoff
2. Loads the original objective, accomplishments, and next actions
3. Injects this context into your current session
4. You can then continue working seamlessly

## Usage

```
/ralph-resume
```

---

## Instructions for Claude

When the user runs `/ralph-resume`:

1. First, check if there's a supervisor session file:
   ```bash
   cat .claude/ralph-supervisor.json 2>/dev/null || echo "{}"
   ```

2. Load the handoff using the TypeScript script:
   ```bash
   bun run "$PLUGIN_ROOT/scripts/load-cycle-handoff.ts" "$(jq -r '.session_id // ""' .claude/ralph-supervisor.json)"
   ```

3. Parse the result and inject the context.

4. If handoff found, display:
   - Original objective
   - What was accomplished in previous cycles
   - Current blockers to address
   - Next actions to take
   - Key learnings to apply

5. Then immediately continue working on the task using the loaded context.

6. If you're in a Ralph loop, remember to output `<promise>COMPLETION_PHRASE</promise>` when truly done.

## Example Output

```
## CYCLE CONTINUATION (Cycle 2)

This is a CONTINUATION of a multi-cycle autonomous run.
Previous cycle (1) ended due to context limits.
Your session data was preserved - continue seamlessly.

### YOUR MISSION (UNCHANGED)
Build a REST API with full test coverage

### WHAT WAS ACCOMPLISHED (Previous Cycles)
- Created project structure
- Implemented GET /users endpoint
- Added basic error handling

### CURRENT BLOCKERS TO ADDRESS
- TypeScript compilation errors in auth.ts

### NEXT ACTIONS (Continue Here)
1. Fix TypeScript errors
2. Implement POST /users endpoint
3. Add input validation

### KEY LEARNINGS (Apply These!)
- Use zod for validation instead of manual checks
- Remember to handle async errors with try/catch
```

After displaying this, continue working on the task immediately.
