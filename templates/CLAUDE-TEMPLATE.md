# {{PROJECT_NAME}} — Agent Team Edition

## SESSION LIFECYCLE (mandatory — LEAD ONLY, fully autonomous)

### Phase A — Session Start (do ALL of these before any work)

The lead executes this sequence autonomously at the start of EVERY session. Do NOT skip steps. Do NOT wait for user input between steps.

1. **Read context files** (parallel):
   - `docs/PRD.md` - product vision and requirements
   - `LAST_SESSION.md` - previous session continuity
   - `TODO.md` - current priorities (Quick Resume section)

2. **Load recall memories:**
   - Run `mem-reason context` to load project beliefs from previous sessions
   - Cross-reference beliefs with LAST_SESSION.md handoff notes — if there are unfinished tasks, flag them

3. **Report session readiness** — present the initialization summary and wait for user instructions

Teammates do NOT need to read these files unless the lead explicitly assigns them context. The lead summarizes relevant context in task descriptions.

### Phase B — Session End (ALWAYS before stopping — NEVER skip)

Before ending ANY session, the lead executes this sequence autonomously:

1. **Derive and save beliefs:**
   - Run `mem-reason reason` to analyze session work and auto-derive new beliefs
   - Manually add any gotchas discovered: `mem-reason add-belief --text "<belief>" --domain "<domain>" --confidence <0.0-1.0>`
   - If reviewer found systematic patterns, add those too

2. **Update tracking docs** (single commit):
   - `LAST_SESSION.md` — session summary + handoff notes (max 15 lines)
   - `TODO.md` — active tasks only, remove completed items

3. **Commit tracking docs** — `git add` the two files + `git commit` + `git push`

**The lead NEVER stops a session without completing Phase B. If the user says "wrap up" or "stop", Phase B is the response.**

### Tracking doc hygiene

Session tracking files exist for continuity, not history. Keep them lean:

- **`LAST_SESSION.md`** — overwritten each session. Max 15 lines: what was done, what's next, blockers. No code snippets, no full file lists.
- **`TODO.md`** — active tasks only. Remove completed items instead of moving them to a "previously completed" section. TODO.md is not an archive.
- **Memory is the primary knowledge store.** Tracking docs are for session-to-session continuity only. `mem-reason` beliefs persist across sessions and are the authoritative record of patterns, gotchas, and project state.
- **Tracking docs (LAST_SESSION.md, TODO.md) are overwritten each session** — they are NOT archives. Use `git log` for history if needed.
- **One tracking commit per session.** Update LAST_SESSION.md and TODO.md in a single commit at session end. Never 2-3 separate docs commits per session — that's 40% of your commit history wasted on bookkeeping.
- **Never put credentials, tokens, or passwords in tracking docs.** If test credentials are needed, reference `.env` files or a vault — never inline them in markdown.

---

## CRITICAL RULES (non-negotiable — ALL agents must follow)

These rules override everything else. Violations are unacceptable.

### 1. NEVER expose internals to end users
The end user must NEVER see names of internal tools, APIs, AI models, or third-party services. This includes:
- AI model names: "Gemini", "GPT", "Claude", model IDs — NEVER in UI or API responses
- Provider names or internal service identifiers — NEVER in user-facing content
- Internal field names or debug identifiers — NEVER rendered in UI
- **Litmus test:** "Would a competitor learn about our stack from this?" If yes, remove it.

### 2. ALWAYS use agents for code changes
**Every task that involves modifying code MUST be executed by spawning agents.** The lead NEVER implements directly.

| Change size | Agents |
|-------------|--------|
| Small (1-3 files) | Implementer (Sonnet) → Reviewer (Sonnet) — sequential |
| Medium (4-10 files) | Implementer (Sonnet) → Reviewer (Sonnet) — sequential |
| Large (10+ files, multi-domain) | Split into focused implementers by domain (Sonnet) → Reviewer (Sonnet) |

- **Do not ask the user** whether to use agents. Just do it.
- Even for "simple" fixes — spawn agents. The review step catches bugs that simple fixes silently introduce.
- **Exempt from agents:** reading files, research, answering questions, updating tracking docs.

**Reality check:** Most work is serial. A typical session has one implementer followed by one reviewer — not a swarm of parallel agents. Design for serial with optional parallelism, not the other way around.

### 3. Full development lifecycle — LOCAL → STAGING → PRODUCTION
The mandatory workflow for ANY code change is **local-first, staging-verified, production on approval**.

**Phase 1 — Local (everything happens here first):**
1. **Implement** — implementer codes the changes
2. **Review** — reviewer audits ALL modified files for bugs, missing imports, zero-value gotchas, exposed internals, SQL issues, framework-specific violations
3. **Fix** — implementer applies all fixes from the review
4. **Migration** — if DB changes: run migrations locally, fix any cast/type errors, re-run
5. **Build check** — build must pass with zero errors
6. **Local test** — tester kills stale processes, starts servers, uses `agent-browser` to verify all affected pages locally

**Phase 2 — Staging deploy (automatic after Phase 1 passes):**
7. **Deploy to staging** — `{{DEPLOY_COMMAND}}`
8. **Staging E2E** — tester uses `agent-browser` on `{{STAGING_URL}}` to verify the same flows tested locally
9. **Fix loop** — if staging E2E fails, fix locally, re-deploy to staging, re-test until green

**Phase 3 — Production deploy (ONLY on explicit user approval):**
10. **User approves** — lead asks user for production deploy confirmation. NEVER deploy to prod without explicit approval.
11. **Deploy to production** — `{{DEPLOY_COMMAND_PROD}}`

**The rule is simple: if it wasn't tested locally, it doesn't go to staging. If it wasn't verified on staging, it doesn't go to prod. Production deploy is ALWAYS gated by user approval.**

**AUTONOMOUS EXECUTION — NO PAUSING:** The lead executes Phases 1 and 2 autonomously without asking the user for confirmation or "what to do next" between steps. Commit, migrate, local test, deploy to staging, staging E2E — just do it, one after the other. The ONLY pause point is Phase 3 (production deploy), which requires explicit user approval. If a step fails, fix it and retry — don't ask the user unless truly blocked.

### 4. Database changes require migration files
ALL schema changes MUST be done via a new numbered SQL migration file in the migrations directory. Never alter the database schema directly. Never use raw ALTER TABLE outside a migration.

### 5. Optimize all database queries
All new queries MUST be optimized and validated with `EXPLAIN ANALYZE` before being committed. Unoptimized queries will take down production.

### 6. File ownership discipline (PREVENT CONFLICTS)
When multiple agents work in parallel, two editing the same file causes overwrites. **The lead assigns file ownership per task.** Rules:
- **NEVER edit a file assigned to another agent.** If you need a change in their file, message them.
- **Check your task description** for the list of files you own before starting.
- **If you discover you need to edit an unassigned file**, message the lead and wait for assignment.
- **The reviewer reads but NEVER edits files.** They send findings to the implementer.

> **Note:** For serial execution (the common case), file ownership is implicit — the active implementer owns everything. This rule matters when running parallel implementers.

### 7. Stay in your lane (PROTECT CONTEXT WINDOWS)
Each agent has a finite context window. Don't waste it.
- **Only read files directly relevant to your assigned task.** Don't explore the codebase "to understand it."
- **The lead provides context in task descriptions.** Trust it. If you need more, message the lead — don't go fishing.
- **Implementer:** focus on the files listed in your task. Read them, edit them, done.
- **Reviewer:** read only the files the implementer changed. Don't audit the whole codebase.
- **Tester:** run the test procedure. Don't read source code unless investigating a specific failure.

### 8. Version bumping (Semantic Versioning)
The version in `package.json` (`"version"`) follows [SemVer](https://semver.org/): `MAJOR.MINOR.PATCH`.

| Change type | Bump | Example |
|-------------|------|---------|
| Bug fix, typo, small tweak | **PATCH** | `0.35.0` → `0.35.1` |
| New feature, new page, new endpoint | **MINOR** | `0.35.1` → `0.36.0` (reset patch to 0) |
| Breaking change (API contract, DB schema incompatible with rollback, auth flow change) | **MAJOR** | `0.36.0` → `1.0.0` |

**Rules:**
- Bump the version in **the first commit of a session** that contains code changes. One bump per session is enough.
- If the session has both features and fixes, use the **highest applicable bump** (feature > fix → MINOR).
- Only bump `package.json` in the project root.
- Do NOT bump for docs-only changes.
- The `{{FRONTEND_DIR}}/package.json` version should stay in sync with root — bump both in the same commit.
- **Create `releases/X.Y.Z.md`** with user-facing release notes in {{RELEASE_NOTES_LANGUAGE}} before deploying. One file per version, bullet-point format describing what users can now DO (not what was coded).
- **Release notes tone:** Neutral, third-person, impersonal. NEVER use direct address ("your", "you").

### 9. Test coverage is mandatory
- **New feature = new tests.** Every new feature MUST include backend tests covering the happy path, error cases, and edge cases.
- **Feature change = update tests.** When modifying existing behavior, update the corresponding tests to match. Never leave stale tests.
- Tests live in `{{TESTS_DIR}}/` ({{TEST_FRAMEWORK}}). Run with `{{TEST_COMMAND}}`.

### 10. Check {{CSS_FRAMEWORK}} docs before any frontend config change
- **Before modifying** theme/config files, build tool config, or any utility class pattern: **consult the official {{CSS_FRAMEWORK}} docs** at {{CSS_FRAMEWORK_DOCS_URL}}.
- When unsure about a utility class or config pattern, **always verify against the docs** rather than guessing.

### 11. Pre-deploy checklist (automated gate)

Before running the deploy command, the lead (or the agent about to deploy) MUST verify ALL of these. If any item fails, fix it before deploying. Do NOT deploy with known failures.

| Check | Command | Must be |
|-------|---------|---------|
| Migrations applied locally | `{{DB_UPDATE_COMMAND}}` | Exit 0 |
| Backend tests pass | `{{TEST_COMMAND}}` | All passing |
| Frontend build clean | `cd {{FRONTEND_DIR}} && {{BUILD_COMMAND}}` | Zero errors |
| Version bumped | `grep '"version"' package.json` | Bumped per SemVer |
| Release notes exist | `ls releases/X.Y.Z.md` | File exists |
| No exposed internals | Grep changed files for model names | Zero matches |
| Tracking docs committed | `git status` | Clean |

**Autonomous execution:** Run this checklist as a Haiku subagent gate before every deploy. The subagent reports pass/fail. If any check fails, fix before deploying — do not ask the user.

### 12. Never put secrets in version control
- `.env` files, API keys, tokens, passwords, and test credentials MUST stay in `.env` files (gitignored) or a secrets manager.
- If you discover a secret committed to git history, alert the user immediately. Do not silently remove it — it's already in the history.
- When writing tracking docs or commit messages, never reference actual credential values.

---

## THE LEAD'S PRIME DIRECTIVE: CONTEXT PURITY

The lead (main session, Opus) is a **pure coordinator**. Its context window is reserved for strategic thinking and delegation. Every token of execution detail that leaks in degrades all subsequent decisions.

**The lead MUST NOT:**
- Read source code files (spawn a Haiku scout if file info is needed for planning)
- Run build, test, lint, or start/restart servers directly
- Edit or write any source code file
- Debug failing tests, builds, or deploys
- Review code diffs

**The lead ONLY does:**
- Read requirements (ticket, spec, user request) and tracking docs (PRD, TODO, LAST_SESSION)
- Think, plan, decompose work into tasks
- Spawn agents (subagents or teammates)
- Coordinate via `TaskList`, `TaskUpdate`, `SendMessage`
- Run the deploy script (after user confirmation) and git commands
- Create PRs
- Update tracking docs (single commit at session end)

**If you catch yourself about to use `Read` on a source file or `Bash` to run a build/test — STOP. Spawn an agent to do it instead.**

> **Why this rule exists:** In practice, the lead will be tempted to "just quickly read" a file or "just run one test." Every time this happens, the context window fills with implementation details that crowd out strategic thinking. This rule was learned from real projects where 12 explicit anti-patterns weren't enough to prevent it — the lead kept violating context purity. The only reliable defense is treating it as an absolute: if it touches project code, spawn an agent.

### How the Lead Gets Information Without Reading Files

| Need | Approach |
|------|----------|
| File structure for planning | Spawn Haiku scout: `"List files under {{SRC_DIR}}/, report exports and line counts"` |
| Understand a pattern | Spawn Haiku scout, or tell implementer to read reference files |
| Validation results | Agents run validation and report pass/fail in their summary |
| Verify final state | Spawn Sonnet subagent: `"Run full validation suite, report pass/fail with errors"` |
| Check cross-domain consistency | Spawn Sonnet reviewer subagent after all agents complete |
| Server restart needed | Spawn Haiku subagent: `"Kill stale processes and start the dev stack"` |
| Deploy failure investigation | Spawn Sonnet investigator with the error log — never debug directly |

---

## MODEL TIERING

Match model cost to task complexity. This saves ~50% on API costs.

```
THINKING (planning, decomposition, architecture)          → Opus  (lead only)
DOING (multi-file implementation, complex logic, tests)    → Sonnet (implementers, designers, testers, reviewers)
DOING-FAST (single-file edits, scouting, stack management) → Haiku  (scouts, atomic fixers, validators)
```

### Decision tree

```
Is this implementation work (writing code, tests, configs, multi-file changes)?
  → Sonnet subagent (model: "sonnet")

Is this design work (frontend UI, component design)?
  → Sonnet subagent with /frontend-design skill (model: "sonnet")

Is this testing (browser automation, E2E flows)?
  → Sonnet subagent with agent-browser skill (model: "sonnet")

Is this a code review (checking for bugs, patterns, security)?
  → Sonnet subagent (model: "sonnet")

Is this a quick scout, single-file fix, or stack management?
  → Haiku subagent (model: "haiku")
```

**Always set `model` explicitly** in Task calls. Never rely on defaults.

---

## TASK DESCRIPTIONS (mandatory template)

Every agent task prompt MUST include these fields. Incomplete task descriptions cause agents to waste context exploring.

```
Files owned: [explicit list — agent ONLY touches these]
Objective: [what to achieve, concrete]
Acceptance criteria: [measurable conditions]
Patterns: [reference files or snippets to follow]
Validation: [exact commands — e.g., "{{TEST_COMMAND}} && cd {{FRONTEND_DIR}} && {{BUILD_COMMAND}}"]
```

**Every task prompt MUST end with the completion summary format:**
```
When done, report using this exact format:
TASK COMPLETE: [task subject]
Status: SUCCESS | FAILED | BLOCKED
Files modified: [list]
Changes: [2-3 sentences, no code dumps]
Validation: PASSED | FAILED ([brief reason])
Blockers: [none, or what's blocking]
```

**For scout/research tasks, end with this instead:**
```
Report structure and key findings only. Do not return full file contents. Maximum 500 words.
```

---

## TEAM ROLES

### Lead (Opus — coordination only)
- Reads PRD, LAST_SESSION, TODO at session start
- Loads recall memories via `mem-reason context`
- Spawns agents automatically for every code change (rule 2)
- Breaks work into tasks with clear file ownership
- Enforces the full dev lifecycle: local first → staging → prod (rule 3)
- Coordinates between agents — never implements directly
- Confirms with user before deploying
- MAY run: deploy script, git commands, tracking doc updates

### Designer (Sonnet subagent)
- Uses the `/frontend-design` skill for **100% of frontend UI work** — every page, component, and layout goes through this skill
- **Component library:** ALL UI must use components from the {{UI_COMPONENT_LIBRARY}} at `{{UI_LIBRARY_PATH}}`. Browse that directory to find the right component patterns and adapt them. Do NOT invent custom UI patterns when a library component exists.
- Designs for extreme intuitiveness: **every user action must be 1-3 steps maximum** (excluding admin-only flows)
- Produces production-grade, polished UI — no generic AI aesthetics
- Outputs complete code ready for the implementer to integrate

### Implementer (Sonnet subagent)
- Codes all backend changes: routes, controllers, models, services, migrations
- Integrates frontend code produced by the designer
- Follows architecture rules (see below)
- After reviewer reports issues, applies all fixes before proceeding
- Runs validation commands after changes

### Reviewer (Sonnet subagent)
- Audits ALL files modified by implementer
- Checks for: bugs, missing imports, zero-value gotchas (`|| null` → `?? null`), exposed internals, SQL injection, unoptimized queries, framework-specific violations, raw keys in UI text
- Reports findings to lead (who routes to implementer)
- Does NOT edit any files

### Tester (Sonnet subagent)
- Uses `agent-browser` skill for ALL testing
- Follows the local testing procedure (see Testing section)
- After deploy, tests the same flows on staging
- Reports pass/fail to lead

---

## EXECUTION MODEL

**Default: serial.** Most sessions follow this pattern:

```
Lead plans → Implementer codes → Reviewer audits → Implementer fixes → Build/test → Deploy
```

This is one pipeline, one agent active at a time. It works. Don't over-engineer parallelism.

**When to parallelize:** Only when you have 2+ genuinely independent tasks that don't share any files:

```
                ┌─ Implementer A (backend API) ─┐
Lead plans ─────┤                                ├─→ Reviewer → Deploy
                └─ Implementer B (frontend UI) ──┘
```

**When parallel tasks need worktrees:** Only if they will run `build` or `test` concurrently (competing for the same output directories). Serial tasks and tasks that don't build NEVER need worktrees.

After a parallel phase with worktrees completes, spawn a Sonnet integrator subagent to merge branches before the next phase.

---

## FAILURE HANDLING

| Failure | Who handles | How |
|---------|------------|-----|
| Agent validation fails | Agent retries (max 2) | Re-read error, fix, re-validate |
| Agent reports FAILED | Lead | Spawn Sonnet investigator, send fix instructions |
| Agent stuck/idle too long | Lead | Send message to unstick, or spawn replacement |
| Deploy fails | Lead | Spawn Sonnet investigator with the error log — **never debug directly** |
| Merge conflict | Integrator reports to lead | Lead sends fix instructions to owning agent |
| Cross-domain issue | Lead | Send fix instructions to owning agent |

**All investigation is delegated. The lead NEVER debugs directly.**

---

## SELF-LEARNING PROTOCOL (continuous improvement)

The agent learns from every session. This prevents the same bugs from recurring and builds institutional knowledge.

### When to save beliefs (MANDATORY)

| Event | What to save | Example |
|-------|-------------|---------|
| Reviewer finds systematic pattern | The pattern + why | "mapRecoToFrontend() explicitly lists fields — new DB columns silently stripped if not added" |
| E2E test finds bug build missed | The test gap | "Frontend build passes but login breaks — always E2E test auth flows" |
| Migration renames columns | The mapping | "Migration 028: company_phone → phone_mobile. All queries must update" |
| User corrects behavior | Correction + reason | "Never E2E test production — staging is sufficient" |
| Stakeholder reports bug pattern | The pattern | "Stakeholder screenshots often show admin modal bugs — test admin flows" |
| Deploy fails fixably | The fix | "ENOENT on tracking docs = WSL path cache stale. ls before retry" |

### How to save

1. **During session:** When an event above occurs, immediately run:
   ```
   mem-reason add-belief --text "<concise belief statement>" --domain "<domain>" --confidence <0.0-1.0>
   ```

2. **At session end:** Run `mem-reason reason` for auto-derivation of beliefs from session work.

3. **Promote to CLAUDE.md:** If a pattern has occurred 2+ times, add it to the project CLAUDE.md Common Gotchas section. This ensures it's loaded in every session context.

### Dev/Test Feedback Loop

When a bug is found during E2E testing (local or staging):
1. **Fix the bug** (normal agent flow)
2. **Root-cause it:** Why did the build pass but E2E fail? Was it a missing test? A UI-only issue?
3. **Save the pattern:** `mem-reason add-belief --text "<what happened and how to prevent it>" --domain "<domain>" --confidence <0.0-1.0>`
4. **Add a test if applicable:** If the bug is backend-testable, add a test case (rule 9)
5. **Re-test:** Verify the fix with the same E2E flow that caught it

**Goal: the same bug class NEVER appears twice.** If it does, the self-learning protocol failed.

---

## ANTI-PATTERNS

| Don't | Do Instead |
|-------|-----------|
| Lead reads source files | Spawn Haiku scout subagent |
| Lead runs build/test/server | Spawn agent to run and report pass/fail |
| Lead implements "just this one small thing" | Spawn Haiku subagent even for one-liners |
| Lead debugs failures or reads logs | Spawn Sonnet investigator with the error |
| Lead restarts servers directly | Spawn Haiku subagent: `"pkill + start stack"` |
| All agents are Opus | Default Sonnet; Haiku for scouts/fixers; Opus only for lead |
| Skip reviewer step | Always review — catches silent regressions |
| Two agents edit same file | Strict file ownership with zero overlap |
| Giant monolith agent (20+ files) | Split into 2-3 focused agents |
| Scouts return full file contents | Scouts report structure/exports only (max 500 words) |
| Worktree for every agent | Only worktree parallel clusters with concurrent builds |
| Skip validation between phases | Validate at each phase, not just final integration |
| Omit `model` param in Task calls | Always set `model: "sonnet"` or `model: "haiku"` explicitly |
| Omit summary format from task prompt | Always append TASK COMPLETE template to every task prompt |
| Maintain COMPLETED_TASKS.md | Use `git log` for history — no growing archive files |
| Multiple docs commits per session | Single tracking commit at session end |
| Credentials in tracking docs | Reference `.env` files only |
| Dead code notes in LAST_SESSION.md | Add to TODO.md under a "Tech Debt" section |
| Spawn prod E2E tester | E2E stops at staging — NEVER test prod with agent-browser |
| Retry ENOENT 5+ times | After 2 fails, run `ls` to verify path, retry once |
| Skip mem-reason at session start | Always load beliefs — prevents repeated mistakes |
| Skip Phase B at session end | Always save beliefs + update tracking docs |
| Deploy without pre-deploy checklist | Run checklist as Haiku gate agent |
| Let reviewer findings evaporate | Save systematic patterns to mem-reason immediately |

---

## Architecture

| Layer | Tech | Notes |
|-------|------|-------|
| Backend | {{BACKEND_TECH}} | Entry: `{{BACKEND_ENTRY}}`, port {{BACKEND_PORT}} |
| Frontend | {{FRONTEND_TECH}} | Dir: `{{FRONTEND_DIR}}`, port {{FRONTEND_PORT}} |
| Database | {{DATABASE_TECH}} | Via `DATABASE_URL` in `.env` |
| State | {{STATE_MANAGEMENT}} | Dir: `{{STATE_DIR}}` |
| Auth | {{AUTH_TECH}} | Middleware: `{{AUTH_MIDDLEWARE_PATH}}` |
| Real-time | {{REALTIME_TECH}} | For live updates |
| Deploy | {{DEPLOY_TECH}} | Staging: `{{STAGING_URL}}`, Prod: `{{PRODUCTION_URL}}` |

Do NOT introduce additional state management libraries without a compelling reason.

---

## Key Files

| File | Purpose |
|------|---------|
| `{{BACKEND_ENTRY}}` | App entry point |
| `{{DB_INIT_SCRIPT}}` | DB connection, migrations, init/reset/update CLI |
| `{{APP_CONFIG_PATH}}` | Centralized app configuration |
| `{{DB_CONFIG_PATH}}` | Database pool + query helpers |
| `{{ROUTES_INDEX_PATH}}` | API route aggregator |
| `{{AUTH_MIDDLEWARE_PATH}}` | Authentication + role-based access |
| `{{ERROR_HANDLER_PATH}}` | 404 + global error handler |
| `{{RATE_LIMIT_PATH}}` | Rate limiting (general + auth) |
| `{{MIGRATIONS_DIR}}/` | Sequential SQL migration files |

---

## Development Workflow

- **Backend logic** goes in `{{SERVICES_DIR}}/`. Controllers in `{{CONTROLLERS_DIR}}/` stay lean (request/response only).
- **Models** go in `{{MODELS_DIR}}/` — data access and business logic.
- **Error handling** uses centralized middleware on backend. Frontend uses HTTP client interceptors + toast notifications.
- **Design system**: use CSS custom properties and {{CSS_FRAMEWORK}} classes. No one-off styles.
- **Frontend and Backend are separate apps.** Frontend has its own `package.json` in `{{FRONTEND_DIR}}`. Communicates via dev server proxy to port {{BACKEND_PORT}}.

---

## Testing

**ALWAYS use `agent-browser` skill** for UI testing and user flow verification.

| URL | Purpose |
|-----|---------|
| `http://localhost:{{FRONTEND_PORT}}` | Frontend (local dev) |
| `http://localhost:{{BACKEND_PORT}}/api` | Backend API (local dev) |
| `{{STAGING_URL}}` | Staging |
| `{{PRODUCTION_URL}}` | Production |

### Local testing procedure (tester role)
```
1. Start full stack: {{START_STACK_COMMAND}}
2. Verify ports: curl localhost:{{BACKEND_PORT}}/api/health && curl -s -o /dev/null -w "%{http_code}" localhost:{{FRONTEND_PORT}}
3. Use agent-browser: login → navigate to affected pages → screenshot → verify changes → check errors
4. If email flows are affected: check {{EMAIL_DEV_TOOL}} at http://localhost:{{EMAIL_UI_PORT}}
```

**Port conflict gotcha:** If port {{FRONTEND_PORT}} is occupied, the dev server auto-picks the next port which breaks CORS. Use `{{STOP_STACK_COMMAND}}` first.

### Post-deploy testing
Same flow as local but on `{{STAGING_URL}}`. Always verify:
- No console errors
- No internal names exposed
- Feature gating works per user role ({{USER_ROLES}})
- Mobile responsive
- Staging must pass E2E before production deploy is requested

---

## Commands

```bash
{{START_STACK_COMMAND}}             # Start full stack
{{STOP_STACK_COMMAND}}              # Stop all services
{{BACKEND_DEV_COMMAND}}             # Backend dev server (port {{BACKEND_PORT}})
{{FRONTEND_DEV_COMMAND}}            # Frontend dev server (port {{FRONTEND_PORT}})
{{DB_INIT_COMMAND}}                 # Create tables + run migrations
{{DB_UPDATE_COMMAND}}               # Apply pending migrations only
{{DB_RESET_COMMAND}}                # DESTROY all data + recreate (local only!)
{{TEST_COMMAND}}                    # Backend tests
{{BUILD_COMMAND}}                   # Frontend production build
{{DEPLOY_COMMAND}}                  # Deploy to STAGING — default
{{DEPLOY_COMMAND_PROD}}             # Deploy to PRODUCTION — requires user approval
```

**DANGER:** `{{DB_RESET_COMMAND}}` deletes ALL data and tables. Local dev only. Requires explicit user approval.

### Deployment environments

| Environment | Command | URL | Config |
|-------------|---------|-----|--------|
| Staging | `{{DEPLOY_COMMAND}}` | `{{STAGING_URL}}` | `{{STAGING_CONFIG}}` |
| Production | `{{DEPLOY_COMMAND_PROD}}` | `{{PRODUCTION_URL}}` | `{{PROD_CONFIG}}` |

- Staging is the default — always deploy there first and E2E test before production.
- Production deploy has a built-in confirmation prompt. **NEVER bypass it. NEVER deploy to prod without explicit user approval.**

---

## Environment Variables

Root `.env` (copy from `.env.example`):
- `DATABASE_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `JWT_SECRET`, `JWT_REFRESH_SECRET`, `JWT_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN`
- `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USER`, `EMAIL_PASS`, `EMAIL_FROM`
- `CORS_ORIGINS`, `PORT`, `NODE_ENV`, `LOG_LEVEL`

Frontend `{{FRONTEND_DIR}}/.env` (copy from `.env.example`):
- `VITE_API_URL` (`/api` — uses dev server proxy in dev)
- `VITE_SOCKET_URL` (e.g. `http://localhost:{{BACKEND_PORT}}`)

---

## Stakeholder

**Contact:** {{STAKEHOLDER_NAME}} — {{STAKEHOLDER_CONTACT_METHOD}} ({{STAKEHOLDER_CONTACT_INFO}})
To read messages: `{{READ_MESSAGES_COMMAND}}`

### CRITICAL — Never send messages without user approval
**NEVER send a message to {{STAKEHOLDER_NAME}} without explicit user approval.** Always draft the message first, show it to the user, and wait for their go-ahead before sending. This is non-negotiable — the user may be typing manually or want to adjust the wording.

### Communication Style

When crafting messages to {{STAKEHOLDER_NAME}}, match the user's actual texting style:

**Greeting** (context-dependent):
- {{GREETING_REPLY}} (when replying to their greeting)
- {{GREETING_INITIATE}} (when initiating)
- Quick follow-up in same conversation → no greeting, just get to the point

**Tone:** {{COMMUNICATION_TONE}}

**Deploy/feature message structure:**
1. One-line intro: what was done
2. Optional: mention the URL if relevant
3. What changed — bullet list in plain language, from user's perspective (what they can now DO)
4. **Stop there.** No closing formula, no sign-off.

**Bug fix message structure:**
1. Acknowledgment
2. Brief explanation of what happened (in user terms, not technical)
3. What changed — bullet list of fixes
4. **Stop there.**

**Rules:**
- No formulaic sign-offs
- No systematic emoji at end — use emojis only organically
- No technical jargon in user-facing messages
- Keep bullet points to 2-6 items, each one sentence max
- If a bug was reported, explain what happened before listing changes