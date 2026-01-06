# Browser-Lite WSL Installation Guide

Instructions for installing browser-lite globally in WSL and updating project tracking files to use it instead of Chrome DevTools MCP.

---

## Step 1: Install browser-lite in WSL

```bash
# Create skills directory
mkdir -p ~/.claude/skills/browser-lite/scripts

# Copy from Windows installation
cp -r /mnt/c/Users/Karim/.claude/skills/browser-lite/* ~/.claude/skills/browser-lite/

# Install dependencies
cd ~/.claude/skills/browser-lite
npm install
```

**Alternative: Clone fresh (if Windows copy fails)**
```bash
mkdir -p ~/.claude/skills/browser-lite/scripts
cd ~/.claude/skills/browser-lite

# Create package.json
cat > package.json << 'EOF'
{
  "name": "browser-lite",
  "version": "1.0.0",
  "description": "Token-efficient Chrome DevTools CLI for Claude Code",
  "type": "module",
  "dependencies": {
    "puppeteer": "^23.0.0"
  }
}
EOF

npm install
```

Then copy the script files from `/mnt/c/Users/Karim/.claude/skills/browser-lite/scripts/` to `~/.claude/skills/browser-lite/scripts/`.

---

## Step 2: Verify Installation

```bash
# Test navigation
node ~/.claude/skills/browser-lite/scripts/navigate.js --url "https://example.com"

# Expected output (~60 tokens):
# {
#   "status": "success",
#   "url": "https://example.com",
#   "title": "Example Domain",
#   "load_time_ms": 852,
#   ...
# }

# Close browser
node ~/.claude/skills/browser-lite/scripts/close.js
```

---

## Step 3: Update Project Tracking Files

For each project that uses Chrome DevTools MCP (e.g., facturai), update the following files:

### 3.1 Update CLAUDE.md

**Find and replace:**

```markdown
# OLD
| `/test` | Pre-test checklist for Chrome DevTools MCP |

# NEW
| `/test` | Pre-test checklist for browser-lite |
```

```markdown
# OLD
### Testing
- **Chrome DevTools MCP is MANDATORY** for all testing
- Run `/test` before testing to verify prerequisites
- "Should work" ≠ "does work" - always verify visually

# NEW
### Testing
- **browser-lite** is used for all visual testing (token-efficient alternative to DevTools MCP)
- Run `/test` before testing to verify prerequisites
- "Should work" ≠ "does work" - always verify visually

### Browser Testing Commands
| Command | Purpose |
|---------|---------|
| `node ~/.claude/skills/browser-lite/scripts/navigate.js --url "URL"` | Navigate to URL |
| `node ~/.claude/skills/browser-lite/scripts/screenshot.js --name "name"` | Screenshot + description (~100 tokens) |
| `node ~/.claude/skills/browser-lite/scripts/console.js` | Check errors (~150 tokens) |
| `node ~/.claude/skills/browser-lite/scripts/click.js --selector "sel"` | Click element |
| `node ~/.claude/skills/browser-lite/scripts/type.js --selector "sel" --text "text"` | Type into input |
| `node ~/.claude/skills/browser-lite/scripts/close.js` | Close browser |

**Why browser-lite instead of DevTools MCP:**
- Screenshots: ~100 tokens (vs ~50,000 for MCP base64)
- Console: ~150 tokens (vs thousands for full logs)
- Zero startup context cost (MCP loads 26 tools = ~2000 tokens)
```

### 3.2 Update /test Command (if project-specific)

If there's a project-specific `.claude/commands/test.md`, update it:

```markdown
---
description: Pre-test checklist for browser-lite
---

Before testing, verify:

1. **Stack Status** - All required servers running (`/stack`)
2. **Build Status** - No compilation errors
3. **Browser-lite** - Skill installed and working

## Browser Testing Workflow

1. Navigate to target URL:
   ```bash
   node ~/.claude/skills/browser-lite/scripts/navigate.js --url "http://localhost:1337/app/"
   ```

2. Take screenshot (returns text description, not base64):
   ```bash
   node ~/.claude/skills/browser-lite/scripts/screenshot.js --name "login-page"
   ```

3. Check console for errors:
   ```bash
   node ~/.claude/skills/browser-lite/scripts/console.js --level error,warn
   ```

4. Interact with elements:
   ```bash
   node ~/.claude/skills/browser-lite/scripts/type.js --selector "#email" --text "test@assistario.local"
   node ~/.claude/skills/browser-lite/scripts/click.js --selector "button[type=submit]"
   ```

5. Close browser when done:
   ```bash
   node ~/.claude/skills/browser-lite/scripts/close.js
   ```

## Output Location

Full data saved to `.browser-debug/` in project directory:
- `screenshots/` - PNG files (viewable manually)
- `console/` - Full console logs (JSON)
- `network/` - Network request logs (JSON)

Report checklist:

| Check | Status |
|-------|--------|
| Servers | OK/Down |
| Build | OK/Failing |
| Browser-lite | OK/Not installed |
```

### 3.3 Add to LAST_SESSION.md (Next Session)

Add a note in the next session's handoff:

```markdown
## Handoff Notes

- **Browser testing now uses browser-lite** instead of Chrome DevTools MCP
- Token savings: ~50,000 tokens per screenshot → ~100 tokens
- Full screenshots saved to `.browser-debug/screenshots/`
- Commands: see CLAUDE.md "Browser Testing Commands" section
```

### 3.4 Add to TODO.md (One-time task)

```markdown
## Quick Resume

**Current Task:** Update project to use browser-lite for testing
**Status:** in progress

---

## Current Priority

### Migrate from DevTools MCP to browser-lite

- [x] Install browser-lite globally in WSL
- [ ] Update CLAUDE.md testing section
- [ ] Update /test command (if project-specific)
- [ ] Remove chrome-devtools from MCP config (optional)
- [ ] Test browser-lite with project's test flow
```

---

## Step 4: Remove Chrome DevTools MCP (Optional)

If you want to fully remove DevTools MCP to eliminate startup token cost:

The MCP config is stored in `~/.claude.json` under the project path. You can:

1. Remove it via Claude Code: `/mcp remove chrome-devtools`
2. Or manually edit `~/.claude.json` and remove the `chrome-devtools` entry from the project's `mcpServers` object

---

## Token Savings Summary

| Operation | Chrome DevTools MCP | browser-lite | Savings |
|-----------|---------------------|--------------|---------|
| Startup (26 tools) | ~2,000 tokens | 0 tokens | 100% |
| Screenshot | ~50,000 tokens | ~100 tokens | 99.8% |
| Console | ~5,000 tokens | ~150 tokens | 97% |
| Network | ~10,000 tokens | ~120 tokens | 98.8% |

**Typical test session:**
- DevTools MCP: ~70,000+ tokens
- browser-lite: ~500 tokens

---

## Quick Reference Card

```bash
# Navigate
node ~/.claude/skills/browser-lite/scripts/navigate.js --url "http://localhost:1337/app/"

# Screenshot (returns description, saves PNG)
node ~/.claude/skills/browser-lite/scripts/screenshot.js --name "test-state"

# Console errors only
node ~/.claude/skills/browser-lite/scripts/console.js

# Click
node ~/.claude/skills/browser-lite/scripts/click.js --selector "#submit-btn"

# Type
node ~/.claude/skills/browser-lite/scripts/type.js --selector "#email" --text "test@example.com"

# Run JS
node ~/.claude/skills/browser-lite/scripts/evaluate.js --script "document.title"

# Network failures
node ~/.claude/skills/browser-lite/scripts/network.js --failed-only

# Close browser
node ~/.claude/skills/browser-lite/scripts/close.js
```
