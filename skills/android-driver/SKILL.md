---
name: android-driver
description: Controls Android devices for mobile app testing. Use when the user asks to "test the app", "tap button", "scroll screen", "check the UI", "automate Android", or mentions testing on a phone/device.
allowed-tools: Bash
---

# Android Driver

Control Android device via AgentBridge. Output is token-optimized (~200 tokens vs ~5000 for raw XML).

**First time setup?** See [INSTALL.md](INSTALL.md)

## Command Format

```bash
python ~/.claude/skills/android-driver/scripts/bridge.py <command>
```

## The Loop

**Always follow: SCAN → DECIDE → ACT → REPEAT**

```bash
# 1. SCAN - see interactive elements
python ~/.claude/skills/android-driver/scripts/bridge.py scan
# Returns: [{"id": 0, "cls": "Button", "txt": "Login"}, ...]

# 2. DECIDE - pick element by txt/desc, note the id

# 3. ACT
python ~/.claude/skills/android-driver/scripts/bridge.py tap <id>
python ~/.claude/skills/android-driver/scripts/bridge.py type <id> "text"
python ~/.claude/skills/android-driver/scripts/bridge.py scroll down
python ~/.claude/skills/android-driver/scripts/bridge.py back

# 4. REPEAT - scan again after each action
```

## Rules

1. **Always scan first** - never guess IDs
2. **IDs reset each scan** - don't cache between scans
3. **Element not found?** - scroll and scan again
4. **Never use raw adb** - use the bridge only

For full command reference, see [REFERENCE.md](REFERENCE.md).
