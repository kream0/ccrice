---
name: android-driver
description: Controls Android devices for mobile app testing. Use when the user asks to "test the app", "tap button", "scroll screen", "check the UI", "automate Android", or mentions testing on a phone/device.
allowed-tools: Bash
---

# Android Driver

Control Android device via AgentBridge. Output is token-optimized (~200 tokens vs ~5000 for raw XML).

## Command Format

**IMPORTANT:** Use Windows Python with Windows-style paths (forward slashes):

```bash
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" <command>
```

**DO NOT use WSL paths like `/mnt/c/...` as the script path** - Windows Python cannot read them.

## The Loop

**Always follow: SCAN → DECIDE → ACT → REPEAT**

```bash
# 1. SCAN - see interactive elements
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" scan
# Returns: [{"id": 0, "cls": "Button", "txt": "Login"}, ...]

# 2. DECIDE - pick element by txt/desc, note the id

# 3. ACT
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" tap <id>
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" type <id> "text"
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" scroll down
/mnt/c/Windows/py.exe "C:/Users/Karim/Documents/work/_tools/AI/agentbridge/bridge.py" back

# 4. REPEAT - scan again after each action
```

## Rules

1. **Always scan first** - never guess IDs
2. **IDs reset each scan** - don't cache between scans
3. **Element not found?** - scroll and scan again
4. **Never use raw adb** - use the bridge only
5. **Always use Windows paths** - `C:/...` not `/mnt/c/...` for the script

For full command reference, see [REFERENCE.md](REFERENCE.md).
