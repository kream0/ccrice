---
description: Generate and display a live system status page. Usage: /fang-status
---

Run `~/fang/display/fang-status` to generate a system status page and push it to the display dashboard.

The script gathers: WhatsApp status, disk/RAM/load, service health (all 5 systemd units), and live output from all tmux panes. It generates a styled HTML page and pushes it via fang-show.

```bash
~/fang/display/fang-status
```

Returns the URL. Send it to the owner.

For JSON output (no display push): `~/fang/display/fang-status --json`

**NEVER gather this data manually.** Always use this script. It is deterministic and consistent.
