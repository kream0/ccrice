---
description: Push content to the Fang Display dashboard for the owner to view. Usage: /fang-show <type> <content>
---

You have a display server at `~/fang/display/` that serves content at `https://fang.elightstudios.fr/display`. Use the `~/fang/display/fang-show` CLI to push content.

## Commands

```bash
# Show copyable text (solves cross-pane selection issue)
~/fang/display/fang-show text "any text content the owner needs to copy"

# Serve a file (image, PDF, video, etc.)
~/fang/display/fang-show file /path/to/image.png

# Show HTML content inside the display shell (nav + styling included)
~/fang/display/fang-show html "<h1>Title</h1><p>Content with <code>formatting</code></p>"

# Serve a full standalone HTML file as-is (webapp, dashboard, chart)
~/fang/display/fang-show raw /path/to/full-page.html

# Generate and display a QR code
~/fang/display/fang-show qr "https://example.com"

# Push a stats/dashboard page (JSON input)
~/fang/display/fang-show stats '{"type":"html","title":"KPI Report","content":"<div>...</div>","name":"kpi.html"}'

# Check display server status
~/fang/display/fang-show status
```

## Instructions

The user said: $ARGUMENTS

Based on their request:

1. Determine what type of content needs to be displayed.
2. Run the appropriate `fang-show` command.
3. Return the URL to the user so they can open it in a browser tab.

## When to use this

- **QR codes** — terminal can't render them properly, push via `fang-show qr`
- **Copyable text** — ttyd split panes cause cross-pane text selection, push via `fang-show text`
- **Images/media** — terminal can't display images, push via `fang-show file`
- **Stats/charts** — generate HTML with charts (recharts, chart.js CDN) and push via `fang-show raw`
- **Webapp sandbox** — build a full HTML page and push via `fang-show raw`
- **Reports** — format as styled HTML and push via `fang-show html`

## Building sandbox pages

For stats, dashboards, or interactive content, build a complete HTML file and use `fang-show raw`:

```bash
# Write the HTML to a temp file
cat > /tmp/dashboard.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>body { background: #1a1b26; color: #c0caf5; font-family: monospace; padding: 24px; }</style>
</head>
<body>
  <canvas id="chart"></canvas>
  <script>/* chart code here */</script>
</body>
</html>
HTMLEOF

# Push it
~/fang/display/fang-show raw /tmp/dashboard.html
```

The owner can then open the URL in a separate browser tab.

## Important

- Content is auto-cleaned after 24 hours.
- The display dashboard at `/display` shows all pushed content as a card grid.
- All content is behind the same basic auth as the terminal.
- Always return the full URL so the owner can click/tap it.
