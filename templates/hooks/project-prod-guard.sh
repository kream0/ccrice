#!/bin/bash
# Hook: PreToolUse[Bash] — Production Guard
# Purpose: Deterministic guard that blocks project agents from touching production.
# Reads ~/fang/projects.json at runtime for prod VPS IPs and prod paths.
# Parses ~/.ssh/config to resolve Host aliases to prod IPs.
# Blocks: deploy to prod, SSH/rsync/scp to prod IPs or aliases, systemctl via SSH,
#         git push to production/prod branches, destructive HTTP to prod domains,
#         indirect execution (bash -c, eval, env) targeting prod, non-.sh deploy tools.
# Allows: staging/dev/local deploys, localhost SSH, local dev servers, safe branches,
#         staging ports on shared VPS, git commits mentioning prod.
# Exit 0 = allow, exit 2 = block with stderr message.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Only guard Bash commands
[ "$TOOL" != "Bash" ] && exit 0

# Allow empty commands
[ -z "$CMD" ] && exit 0

# ── Load prod infrastructure from projects.json ──
PROJECTS_FILE="$HOME/fang/projects.json"
PROD_IPS=""
PROD_PATHS=""

if [ -f "$PROJECTS_FILE" ]; then
  # Extract all prod_vps values (deduplicated)
  PROD_IPS=$(jq -r '.projects[].prod_vps // empty' "$PROJECTS_FILE" 2>/dev/null | sort -u)
  # Extract all prod_path values
  PROD_PATHS=$(jq -r '.projects[].prod_path // empty' "$PROJECTS_FILE" 2>/dev/null | sort -u)
fi

# Fallback: if projects.json is missing or unreadable, use known IP
if [ -z "$PROD_IPS" ]; then
  PROD_IPS="167.235.153.214"
fi

# ── Parse SSH config for Host→HostName aliases ──
# Build list of aliases whose HostName matches a prod IP
PROD_ALIASES=""
SSH_CONFIG="$HOME/.ssh/config"
if [ -f "$SSH_CONFIG" ]; then
  # Single-pass awk: extract Host aliases whose HostName matches a prod IP
  IP_PATTERN=$(echo "$PROD_IPS" | tr '\n' '|' | sed 's/|$//')
  PROD_ALIASES=$(awk -v ips="$IP_PATTERN" '
    /^[[:space:]]*#/ { next }
    /^[Hh]ost[[:space:]]/ && !/\*/ && !/\?/ {
      # Capture ALL aliases on the Host line (handles "Host a b c")
      delete hosts; nhosts=0
      for (i=2; i<=NF; i++) { nhosts++; hosts[nhosts]=$i }
      next
    }
    /^[[:space:]]*[Hh]ost[Nn]ame[[:space:]]/ && nhosts > 0 {
      gsub(/^[[:space:]]+/, "", $2)
      n = split(ips, arr, "|")
      for (i = 1; i <= n; i++) {
        if ($2 == arr[i]) {
          for (j = 1; j <= nhosts; j++) print hosts[j]
          break
        }
      }
    }
  ' "$SSH_CONFIG")
fi

# ── Helper: check if command targets a prod IP or prod alias ──
targets_prod_ip() {
  local cmd="$1"
  # Check literal IPs
  while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    if echo "$cmd" | grep -qF "$ip"; then
      echo "$ip"
      return 0
    fi
  done <<< "$PROD_IPS"
  # Check SSH aliases
  while IFS= read -r alias; do
    [ -z "$alias" ] && continue
    if echo "$cmd" | grep -qwF "$alias"; then
      echo "$alias"
      return 0
    fi
  done <<< "$PROD_ALIASES"
  return 1
}

# ── Helper: check if command targets a prod path on remote ──
targets_prod_path() {
  local cmd="$1"
  while IFS= read -r ppath; do
    [ -z "$ppath" ] && continue
    if echo "$cmd" | grep -qF "$ppath"; then
      echo "$ppath"
      return 0
    fi
  done <<< "$PROD_PATHS"
  return 1
}

# ── Helper: emit block message ──
block() {
  local what="$1"
  local instead="$2"
  echo "BLOCKED — Production guard triggered" >&2
  echo "  What: $what" >&2
  echo "  Instead: $instead" >&2
  echo "" >&2
  echo "Production deploys require manual approval. Use staging or dev environments." >&2
  exit 2
}

# ── Helper: emit warning (non-blocking) ──
warn() {
  local what="$1"
  echo "WARNING — Production guard: $what" >&2
}

# ── Meta-rule (Fix #2): Indirect execution targeting prod ──
# If the command contains a prod IP or alias ANYWHERE, and also contains a
# remote-targeting keyword ANYWHERE, block it. This catches bash -c, eval,
# env, xargs, pipes, subshells — any wrapper that hides the real command.
MATCHED_ANYWHERE=$(targets_prod_ip "$CMD")
if [ -n "$MATCHED_ANYWHERE" ]; then
  if echo "$CMD" | grep -qiE '\b(ssh|rsync|scp|systemctl|deploy)\b'; then
    # Allow through if this is a simple direct command that later rules handle
    # with more precision. Only fire the meta-rule for indirect/wrapped execution.
    if echo "$CMD" | grep -qE '(bash\s+-c|sh\s+-c|\beval\s|\benv\s|\bxargs\s|`|\$\()'; then
      block "Indirect execution targeting production ($MATCHED_ANYWHERE)" \
            "Run commands directly against staging/dev, not through wrappers"
    fi
  fi
fi

# ── Fix #3: Variable expansion warning ──
# If command uses ssh/rsync/scp with variable references in host position,
# warn about potential prod targeting (non-blocking).
if echo "$CMD" | grep -qE '\b(ssh|rsync|scp)\b'; then
  if echo "$CMD" | grep -qE '(\$[A-Za-z_]|\$\{|`|\$\()'; then
    # Don't warn if clearly targeting localhost
    if ! echo "$CMD" | grep -qE '\b(localhost|127\.0\.0\.1)\b'; then
      warn "Command uses variable expansion with ssh/rsync/scp — verify it does not target production"
    fi
  fi
fi

# ── Rule 1: Deploy scripts/tools with "prod" or "production" argument ──
# (Fix #4: broadened to non-.sh tools; Fix #5: matches "production" too)

# 1a: Shell deploy scripts: ./deploy-*.sh prod, bash deploy*.sh, sh deploy*.sh
if echo "$CMD" | grep -qE '(^|[;&|]\s*)(\.\/|bash\s+|sh\s+)deploy[^ ]*\.sh\s+.*\b(prod|production)\b'; then
  block "Deploy script called with prod/production argument" \
        "Use 'staging' or 'dev' argument instead (e.g., ./deploy.sh staging)"
fi

# 1b: npm/yarn/pnpm/bun run deploy with prod
if echo "$CMD" | grep -qE '\b(npm|yarn|pnpm|bun)\s+run\s+deploy.*\b(prod|production)\b'; then
  block "Package manager deploy targeting production" \
        "Use 'staging' or 'dev' deploy target instead"
fi

# 1c: make deploy with prod
if echo "$CMD" | grep -qE '\bmake\s+deploy[^ ]*\s*.*\b(prod|production)\b'; then
  block "make deploy targeting production" \
        "Use 'make deploy-staging' or similar instead"
fi

# 1d: node/python/ruby deploy scripts with prod argument
if echo "$CMD" | grep -qE '\b(node|python3?|ruby)\s+deploy[^ ]*\s+.*\b(prod|production)\b'; then
  block "Deploy script (node/python/ruby) targeting production" \
        "Use 'staging' or 'dev' argument instead"
fi

# 1e: Any executable with "deploy" in name AND "prod/production" as argument
# Catches: ./custom-deploy prod, /path/to/deploy-thing production
# Avoids: grep "production" deploy.log, NODE_ENV=production npm run build
if echo "$CMD" | grep -qE '(^|[;&|]\s*)(\.?\/)?[^ ]*deploy[^ ]*\s+.*\b(prod|production)\b'; then
  # Exclude read-only commands (grep, cat, less, tail, head, wc)
  if ! echo "$CMD" | grep -qE '(^|[;&|]\s*)(grep|cat|less|tail|head|wc|awk|sed)\s'; then
    # Exclude NODE_ENV=production (build-time var, not deploy target)
    if ! echo "$CMD" | grep -qE 'NODE_ENV=(prod|production)\b'; then
      block "Deploy command targeting production" \
            "Use 'staging' or 'dev' argument instead"
    fi
  fi
fi

# ── Rule 2: SSH to prod VPS IPs or aliases ──
if echo "$CMD" | grep -qE '(^|[;&|]\s*)ssh\s'; then
  # Check prod IP/alias FIRST — even if localhost appears (ProxyJump bypass)
  MATCHED_IP=$(targets_prod_ip "$CMD")
  if [ -n "$MATCHED_IP" ]; then
    block "SSH to production VPS ($MATCHED_IP)" \
          "SSH to staging/dev server or use localhost for testing"
  fi
fi

# ── Rule 3: Rsync/scp to prod VPS IPs or aliases ──
if echo "$CMD" | grep -qE '(^|[;&|]\s*)(rsync|scp)\s'; then
  MATCHED_IP=$(targets_prod_ip "$CMD")
  if [ -n "$MATCHED_IP" ]; then
    block "rsync/scp targeting production VPS ($MATCHED_IP)" \
          "Use staging/dev server as target instead"
  fi
fi

# ── Rule 4: Commands referencing prod paths + prod IPs (remote context) ──
# (Fix #7: Only fire for remote-targeting tools, not echo/git/cat/printf)
if [ -n "$PROD_PATHS" ]; then
  MATCHED_PATH=$(targets_prod_path "$CMD")
  if [ -n "$MATCHED_PATH" ]; then
    MATCHED_IP=$(targets_prod_ip "$CMD")
    if [ -n "$MATCHED_IP" ]; then
      # Only block if command starts with (or chains to) a remote-targeting tool
      if echo "$CMD" | grep -qE '(^|[;&|]\s*)(ssh|rsync|scp|curl|wget)\s'; then
        block "Command targets production path ($MATCHED_PATH) on production VPS ($MATCHED_IP)" \
              "Use staging paths or local paths for testing"
      fi
    fi
  fi
fi

# ── Rule 5: systemctl via SSH to prod ──
if echo "$CMD" | grep -qE 'ssh\s.*systemctl\s'; then
  MATCHED_IP=$(targets_prod_ip "$CMD")
  if [ -n "$MATCHED_IP" ]; then
    block "systemctl command via SSH to production VPS ($MATCHED_IP)" \
          "Run systemctl on staging/dev server or test locally"
  fi
fi

# ── Rule 6: git push to production/prod branches ──
# (Fix #6: require end-of-line, whitespace, or command separator after branch name)
if echo "$CMD" | grep -qE '(^|[;&|]\s*)git\s+push\s'; then
  # Block push to branches named exactly "production" or "prod" (not production-fix, prod-hotfix)
  # Handles flags before remote: git push --force origin production
  if echo "$CMD" | grep -qE 'git\s+push\s+(-[^ ]+\s+)*\S+\s+(production|prod)\s*($|[;&|])'; then
    block "git push to production/prod branch" \
          "Push to main, develop, staging, or a feature branch instead"
  fi
  # Also catch push with refspec like origin HEAD:prod
  if echo "$CMD" | grep -qE 'git\s+push\s.*:(production|prod)\s*($|[;&|])'; then
    block "git push to production/prod branch (refspec)" \
          "Push to main, develop, staging, or a feature branch instead"
  fi
fi

# ── Rule 7: Destructive HTTP to prod domains ──
# (Fix #8: Allow non-standard ports — staging runs on same VPS with ports != 80/443)
if echo "$CMD" | grep -qE '(curl|wget)\s'; then
  if echo "$CMD" | grep -qE -- '-X\s*(DELETE|PUT)\b|--request\s*(DELETE|PUT)\b'; then
    MATCHED_IP=$(targets_prod_ip "$CMD")
    if [ -n "$MATCHED_IP" ]; then
      # Allow if URL targets a non-standard port (staging heuristic)
      # Match IP:port or alias:port where port is NOT 80 or 443
      if echo "$CMD" | grep -qE "${MATCHED_IP}:[0-9]+" 2>/dev/null; then
        PORT=$(echo "$CMD" | grep -oE "${MATCHED_IP}:([0-9]+)" | head -1 | grep -oE '[0-9]+$')
        if [ "$PORT" != "80" ] && [ "$PORT" != "443" ]; then
          # Non-standard port = staging, allow it
          exit 0
        fi
      fi
      block "Destructive HTTP request (DELETE/PUT) targeting production ($MATCHED_IP)" \
            "Use staging/dev API endpoint or test with GET first"
    fi
  fi
fi

# ── All checks passed ──
exit 0
