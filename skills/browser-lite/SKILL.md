---
name: browser-lite
description: Token-efficient browser debugging. Use when user asks to debug browser, take screenshot, check console errors, click element, navigate to URL, test webpage, or mentions Chrome DevTools, Puppeteer, web testing, browser automation.
allowed-tools: Bash, Read
---

# Browser-Lite: Token-Efficient Browser Debugging

Provides Chrome automation with minimal context window usage. Saves full data to `.browser-debug/`, returns only actionable summaries.

## Commands

### Navigate to URL
```bash
node ~/.claude/skills/browser-lite/scripts/navigate.js --url "http://localhost:3000"
```

### Take Screenshot (with text description)
```bash
node ~/.claude/skills/browser-lite/scripts/screenshot.js --name "page-state"
```

### Check Console Errors
```bash
node ~/.claude/skills/browser-lite/scripts/console.js --level error,warn
```

### Click Element
```bash
node ~/.claude/skills/browser-lite/scripts/click.js --selector "button.submit"
```

### Type Text
```bash
node ~/.claude/skills/browser-lite/scripts/type.js --selector "#email" --text "user@test.com"
```

### Run JavaScript
```bash
node ~/.claude/skills/browser-lite/scripts/evaluate.js --script "document.title"
```

### Check Network Requests
```bash
node ~/.claude/skills/browser-lite/scripts/network.js --failed-only
```

### Close Browser
```bash
node ~/.claude/skills/browser-lite/scripts/close.js
```

## Output Location

Full output saved to `.browser-debug/` in working directory:
- `screenshots/` - PNG files
- `console/` - Console logs (JSON)
- `network/` - Network logs (JSON)
- `state.json` - Browser session state

## Why This Exists

Chrome DevTools MCP consumes massive tokens:
- Screenshots as base64: ~50,000 tokens each
- Full console logs: thousands of tokens
- This skill: ~100-200 tokens per operation
