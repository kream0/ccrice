---
description: "PR review comparing branches or commits. Usage: /pr-review SOURCE TARGET [--ref REFERENCE] [--sync]"
---

# PR Review: $ARGUMENTS

Review a pull request comparing two branches or commit hashes, optionally using a reference branch for architectural patterns.

## Parse Arguments

Extract from `$ARGUMENTS`:
- **SOURCE**: First argument (the feature/PR branch OR a commit hash)
- **TARGET**: Second argument (the base branch, e.g., main, develop, OR a commit hash)
- **REFERENCE**: Optional `--ref <branch>` flag for pattern reference
- **AUTO_SYNC**: Optional `--sync` flag to automatically fetch and pull without prompting

Both SOURCE and TARGET can be:
- Branch names (e.g., `feature-auth`, `main`)
- Full commit hashes (e.g., `a1b2c3d4e5f6...`)
- Short commit hashes (e.g., `a1b2c3d`)

Examples:
- `/pr-review feature-auth main` → SOURCE=feature-auth, TARGET=main
- `/pr-review feature-auth main --ref gold-patterns` → with reference branch
- `/pr-review a1b2c3d main` → compare commit to branch
- `/pr-review a1b2c3d e4f5g6h` → compare two commits
- `/pr-review feature-auth main --sync` → auto-sync before review
- `/pr-review feature-auth main --sync --ref gold-patterns` → all options

---

## Step 0: Validate and Sync References

Before starting the review, validate that the specified branches/commits exist and are in sync.

### 0.1: Check if references exist locally

```bash
# Check if SOURCE exists (as branch or commit)
git rev-parse --verify SOURCE 2>/dev/null

# Check if TARGET exists (as branch or commit)
git rev-parse --verify TARGET 2>/dev/null

# If REFERENCE is provided, check it too
git rev-parse --verify REFERENCE 2>/dev/null
```

**If any reference doesn't exist locally:**
- Stop and notify the user: "The reference 'X' does not exist locally. Please check the name or fetch it first."

### 0.2: Check sync status with origin (for branches only)

For each reference that is a branch (not a commit hash), check if it's synced with origin:

```bash
# Fetch latest refs from origin (without pulling)
git fetch origin --dry-run 2>&1

# For SOURCE (if it's a branch):
git rev-parse SOURCE 2>/dev/null
git rev-parse origin/SOURCE 2>/dev/null
# Compare: if different, branch is not synced

# For TARGET (if it's a branch):
git rev-parse TARGET 2>/dev/null
git rev-parse origin/TARGET 2>/dev/null
# Compare: if different, branch is not synced
```

**If any branch is out of sync with origin:**

- **If `--sync` flag is provided:** Automatically fetch and pull the out-of-sync branches:
  ```bash
  git fetch origin SOURCE:SOURCE 2>/dev/null || git fetch origin
  git fetch origin TARGET:TARGET 2>/dev/null || git fetch origin
  ```

- **If `--sync` flag is NOT provided:** Stop and ask the user:
  > "The following branches are out of sync with origin:
  > - SOURCE (local: abc123, origin: def456)
  > - TARGET (local: xyz789, origin: uvw012)
  >
  > Would you like me to fetch and update them before proceeding?"

  Wait for user confirmation before continuing.

### 0.3: Check for empty diff

```bash
# Check if there are any differences between SOURCE and TARGET
git diff TARGET...SOURCE --quiet
echo $?  # 0 = no differences, 1 = differences exist
```

**If there is no diff (exit code 0):**
- Stop and notify the user: "There are no differences between SOURCE and TARGET. Nothing to review."
- Do NOT proceed with the review.

---

## Step 1: Gather Context

Run these commands to understand the PR scope:

```bash
# List commits in this PR
git log --oneline TARGET..SOURCE

# Get the full diff
git diff TARGET...SOURCE --stat

# Get detailed diff
git diff TARGET...SOURCE
```

If REFERENCE branch is provided:
```bash
# Identify key architectural files in reference branch
git ls-tree -r --name-only REFERENCE | grep -E '\.(ts|js|py|go|java|rs)$' | head -20
```

---

## Step 2: Review Checklist

Analyze the diff against these criteria:

### Code Quality
- [ ] No obvious bugs or logic errors
- [ ] Error handling is appropriate
- [ ] No hardcoded secrets or credentials
- [ ] No debug code left in (console.log, print, etc.)

### Security (OWASP considerations)
- [ ] Input validation present where needed
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities
- [ ] Authentication/authorization properly handled

### Best Practices
- [ ] Consistent naming conventions
- [ ] Functions are reasonably sized
- [ ] No code duplication introduced
- [ ] Tests added/updated for changes

### Architecture (if REFERENCE branch provided)
- [ ] Follows patterns established in REFERENCE branch
- [ ] Directory structure consistent with REFERENCE
- [ ] Similar abstractions and design patterns used
- [ ] Naming conventions match REFERENCE style

---

## Step 3: Reference Branch Analysis (if provided)

When a REFERENCE branch is specified, perform deeper pattern comparison:

```bash
# Get structure of key directories in reference
git show REFERENCE:src/ 2>/dev/null | head -20

# Compare file organization
git diff TARGET...SOURCE --stat | awk '{print $1}' | while read f; do
  dir=$(dirname "$f")
  echo "Changed: $dir"
done | sort -u
```

For each changed directory, check if similar patterns exist in REFERENCE:
- Component structure
- Service/repository patterns
- Error handling approaches
- Testing patterns

---

## Step 4: Generate Review Report

Provide a structured review:

### Summary
Brief overview of what this PR accomplishes.

### Changes Overview
| File | Type | Impact | Notes |
|------|------|--------|-------|
| path/to/file | Added/Modified/Deleted | High/Medium/Low | Brief note |

### Findings

#### Critical (must fix)
- List blocking issues

#### Warnings (should fix)
- List recommended changes

#### Suggestions (nice to have)
- List optional improvements

### Pattern Compliance (if REFERENCE provided)
| Aspect | Reference Pattern | PR Implementation | Match |
|--------|-------------------|-------------------|-------|
| Structure | How REFERENCE does it | How PR does it | Yes/No/Partial |

### Verdict
- **Approve**: Ready to merge
- **Request Changes**: Blocking issues found
- **Comment**: Non-blocking feedback provided

---

## Output Format

Always conclude with:

```
## PR Review Summary

**Source:** SOURCE (resolved: <full-commit-hash>) → **Target:** TARGET (resolved: <full-commit-hash>)
**Reference:** REFERENCE (or "None")
**Sync Status:** [Synced | Auto-synced with --sync | Synced after user confirmation]
**Verdict:** [Approve | Request Changes | Comment]

**Key Findings:**
1. [Most important finding]
2. [Second most important]
3. [Third most important]

**Action Items:**
- [ ] [Required change 1]
- [ ] [Required change 2]
```
