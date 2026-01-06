---
description: Initialize session context by reading tracking files and checking stack status
---

Read the following files to establish session context:

1. Read `docs/PRD.md` (or `PRD.md`) if it exists - to understand product vision
2. Read `LAST_SESSION.md` to understand what was accomplished in the previous session
3. Read `TODO.md` to see current priorities and the Quick Resume section
4. Read `BACKLOG.md` for long-term roadmap context (first 50 lines is enough)

After reading, provide a brief summary in this format:

---
**Session Initialization Complete**

| Item | Status |
|------|--------|
| Previous Session | Session # - [focus area] |
| Current Task | [from TODO.md Quick Resume] |

**Ready to proceed:** Yes / No (if no, explain what needs to be fixed)
---

Do NOT start implementing anything yet - wait for user instructions.
