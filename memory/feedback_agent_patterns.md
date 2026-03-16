---
name: Agent Work Patterns
description: Learned patterns for how to work effectively with this user — context purity, agent delegation, no bloat
type: feedback
---

Lead agent must follow these patterns (learned from cosware project analysis):

1. **Never read project source code as lead.** Spawn agents for everything. The cosware CLAUDE.md has 12 anti-patterns because the lead kept breaking this rule. Enforce architecturally (separate directories/sessions), not just by instruction.

2. **No markdown tracking file bloat.** The cosware project had 40% docs commits (LAST_SESSION.md, TODO.md, COMPLETED_TASKS.md). Use memr beliefs instead. No session tracking markdown.

3. **Design for serial execution.** The cosware "agent team" (parallel worktrees, dependency graphs) was never actually used — all 197 commits were serial on main. Don't over-engineer parallelism.

4. **The review step is non-negotiable.** It caught real critical bugs (9 stale references, silently dropped fields). Always implement → review → fix.

5. **Batch tracking updates.** If tracking docs must exist, one commit at session end, not 2-3 per session.

**Why:** These patterns emerged from critical analysis of 68 cosware sessions. Ignoring them leads to context pollution, wasted tokens, and the user having to repeatedly correct the agent.

**How to apply:** When working on any project with this user, default to spawning agents for implementation, never read source as lead, and prefer memr beliefs over markdown tracking files.
