# AgentBridge Command Reference

## Commands

| Command | Description |
|---------|-------------|
| `scan` | Get interactive UI elements as JSON |
| `scan --all` | Include non-interactive elements |
| `scan --compact` | Single-line JSON output |
| `tap <id>` | Tap element center |
| `tap <id> --long` | Long press (default 0.5s) |
| `tap <id> --long --duration 1.0` | Long press with custom duration |
| `type <id> "text"` | Type into element |
| `type <id> "text" --clear` | Clear field then type |
| `type <id> "text" --enter` | Type and press enter |
| `type <id> "text" --clear --enter` | Clear, type, submit |
| `scroll down` | Scroll to reveal content below |
| `scroll up` | Scroll to reveal content above |
| `scroll left` | Scroll to reveal content left |
| `scroll right` | Scroll to reveal content right |
| `scroll down --distance 0.8` | Scroll 80% of screen |
| `back` | Press back button |
| `home` | Press home button |
| `key <name>` | Press key (enter, menu, etc.) |
| `screenshot` | Capture screen (base64 PNG) |
| `info` | Device info JSON |
| `status` | Connection status |

## Element Fields

| Field | Description |
|-------|-------------|
| `id` | Numeric ID for commands |
| `cls` | Class name (Button, EditText, etc.) |
| `txt` | Text content (max 50 chars) |
| `desc` | Content description (max 50 chars) |
| `res` | Resource ID |
| `bounds` | Position: `{x, y, w, h}` |
| `flags` | State flags (see below) |

## Flags

| Flag | Meaning |
|------|---------|
| `C` | Clickable |
| `L` | Long-clickable |
| `S` | Scrollable |
| `F` | Focusable |
| `K` | Checkable |
| `k` | Checked (state) |
| `D` | Disabled |
| `s` | Selected |
