---
description: "PR review comparing branches. Usage: /pr-review SOURCE TARGET [--ref REFERENCE_BRANCH]"
---

# PR Review: $ARGUMENTS

Review a pull request comparing two branches, optionally using a reference branch for architectural patterns.

## Parse Arguments

Extract from `$ARGUMENTS`:
- **SOURCE**: First argument (the feature/PR branch)
- **TARGET**: Second argument (the base branch, e.g., main, develop)
- **REFERENCE**: Optional `--ref <branch>` flag for pattern reference

Examples:
- `/pr-review feature-auth main` → SOURCE=feature-auth, TARGET=main, REFERENCE=none
- `/pr-review feature-auth main --ref gold-patterns` → SOURCE=feature-auth, TARGET=main, REFERENCE=gold-patterns

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

**Source:** SOURCE → **Target:** TARGET
**Reference:** REFERENCE (or "None")
**Verdict:** [Approve | Request Changes | Comment]

**Key Findings:**
1. [Most important finding]
2. [Second most important]
3. [Third most important]

**Action Items:**
- [ ] [Required change 1]
- [ ] [Required change 2]
```
