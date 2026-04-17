---
description: Publish static webapps to public URLs on fang.elightstudios.fr. Usage: /fang-publish <command> [args]
---

You have a publishing tool at `~/fang/display/fang-publish` that deploys static webapps to `https://fang.elightstudios.fr/apps/<name>/`. Published apps are accessible **without** basic auth (public or code-protected).

## Commands

```bash
# Deploy a static webapp (copies dir contents, registers in dashboard)
~/fang/display/fang-publish deploy <name> <dir> [--title "Human Title"]

# List all published apps
~/fang/display/fang-publish list

# Add passcode protection (visitors must enter code to view)
~/fang/display/fang-publish protect <name> <passcode>

# Remove passcode protection (make public again)
~/fang/display/fang-publish unprotect <name>

# Remove a published app entirely
~/fang/display/fang-publish unpublish <name>
```

## Instructions

The user said: $ARGUMENTS

Based on their request:

1. Determine which fang-publish command to run.
2. If deploying, ensure the source directory exists and contains at least an `index.html`.
3. App names must be lowercase alphanumeric with dashes/underscores only.
4. Run the appropriate command.
5. Return the public URL so the user (or a stakeholder) can open it.

## Workflow for project agents

When a project agent needs to share a webapp with stakeholders:

```bash
# 1. Build the webapp into a directory
#    (project-specific build step)

# 2. Deploy it
~/fang/display/fang-publish deploy my-preview /path/to/build/

# 3. Optionally add code protection for draft sharing
~/fang/display/fang-publish protect my-preview shareCode123

# 4. Share the URL: https://fang.elightstudios.fr/apps/my-preview/
```

## Key details

- Apps are **persistent** — no auto-cleanup (unlike display content's 24h TTL)
- The `/apps/` path bypasses nginx basic auth — apps are either fully public or code-protected
- Code protection uses a passcode form + cookie (7-day expiry, HttpOnly, Secure)
- Published apps appear in the display dashboard with share buttons
- App name constraints: `[a-z0-9_-]+` (lowercase, no spaces)
