---
description: Pre-test checklist before using Chrome DevTools MCP for testing
---

Before testing with Chrome DevTools MCP, verify all prerequisites:

## Step 1: Stack Verification

Run health checks on all 3 servers:
```bash
curl -s http://localhost:1337/app/ | head -3      # Frontend must return HTML
curl -s http://localhost:3001/health              # Backend must return {"status":"healthy"...}
curl -s http://localhost:3000/api/v1/health       # MCP must return {"status":"ok"...}
```

## Step 2: Build Verification

Check that frontend compiled successfully (no TypeScript errors).
Look for "✔ Compiled successfully" in the terminal output.

## Step 3: Chrome DevTools MCP Connection

Verify the browser is connected by taking a snapshot:
```
mcp__chrome-devtools__take_snapshot
```

## Test Credentials

Use these for login testing:
- **Email:** test@assistario.local
- **Password:** test123

## Checklist

| Check | Status |
|-------|--------|
| Frontend (1337) | ✅/❌ |
| Backend (3001) | ✅/❌ |
| MCP (3000) | ✅/❌ |
| Build Success | ✅/❌ |
| Chrome DevTools MCP | ✅/❌ |

## If all checks pass:

Navigate to http://localhost:1337/app/ and begin testing.

## If any check fails:

Report the specific issue and how to fix it before proceeding.

---

**REMINDER:** Chrome DevTools MCP is MANDATORY for all testing. "Should work" ≠ "does work".
