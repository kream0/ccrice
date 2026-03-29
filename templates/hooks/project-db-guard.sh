#!/bin/bash
# Hook: PreToolUse[Bash] — Database Guard
# Purpose: Blocks dangerous database operations by project agents.
#
# Rule 0 — Block self-approval (agent cannot create its own stamp)
#
# Rule 1 — ALWAYS block plaintext database passwords in commands
#   Catches: mysql -pSECRET, --password=SECRET, MYSQL_PWD=SECRET ...
#   Allows:  -p (prompt), -p$VAR, --password=$VAR, env var references
#
# Rule 2 — Block destructive/privilege SQL unless approval stamp exists
#   Catches: UPDATE, DELETE, DROP, TRUNCATE, ALTER, GRANT, REVOKE
#   Allows:  SELECT, SHOW, DESCRIBE, INSERT, CREATE (read + additive)
#   Override: touch /tmp/<project>-db-write-approved (human only, 4h TTL)
#
# Known limitations (regex-based inspection cannot catch):
#   - SQL loaded from files: mysql < destructive.sql, SOURCE file.sql
#   - Encoded commands: base64 -d | bash, eval with obfuscated input
#   - Password via command substitution: -p$(echo secret)
#   These require defense-in-depth at other layers.
#
# Exit 0 = allow, exit 2 = block with stderr message.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

[ "$TOOL" != "Bash" ] && exit 0
[ -z "$CMD" ] && exit 0

# ── Helper ──
block() {
  echo "BLOCKED — Database guard [$1]" >&2
  echo "  What: $2" >&2
  echo "  Instead: $3" >&2
  exit 2
}

# ══════════════════════════════════════════════════════════════════════
# Rule 0: Anti-self-approval — agents cannot create their own stamps
# Must run BEFORE db-client check (touch has no db client keyword)
# ══════════════════════════════════════════════════════════════════════

if echo "$CMD" | grep -qF "db-write-approved"; then
  if echo "$CMD" | grep -qE '\b(touch|mkdir|tee|printf|cp|mv|ln)\b|>[^&]|echo\s.*>'; then
    block "self-approval" \
          "Cannot create database write approval stamps" \
          "A human operator must create the stamp outside Claude Code"
  fi
fi

# ── Detect database client in command ──
HAS_MYSQL=false
HAS_ANY_DB=false

# Match db clients as commands (preceded by start/whitespace/shell operator/quotes),
# NOT as substrings in file paths like /var/log/mysql.log
if echo "$CMD" | grep -qE "(^|[[:space:]|;&(\"'])(mysql|mysqldump|mysqladmin|mariadb|mycli)\b"; then
  HAS_MYSQL=true
  HAS_ANY_DB=true
fi
if echo "$CMD" | grep -qE "(^|[[:space:]|;&(\"'])(psql|pgcli|sqlite3)\b"; then
  HAS_ANY_DB=true
fi

# Exit early if no database client
$HAS_ANY_DB || exit 0

# ══════════════════════════════════════════════════════════════════════
# Rule 1: Block plaintext passwords (ALWAYS — no approval override)
# Plaintext passwords in commands are visible in process lists,
# shell history, and CI logs. Never acceptable.
# ══════════════════════════════════════════════════════════════════════

# 1a: mysql/mariadb short flag: -p<plaintext>
#     -p alone or -p$VAR → OK.  -pActualPassword → BLOCK.
#     Only for mysql-family (psql uses -p for port).
if $HAS_MYSQL; then
  # Require -p to be preceded by whitespace/start — avoids matching inside --password
  if echo "$CMD" | grep -qE '(^|[[:space:]])-p[A-Za-z0-9_./!@#%^&*+=]'; then
    block "plaintext-password" \
          "Plaintext database password in -p flag" \
          "Use: -p\$DB_PASSWORD  or  --password=\$DB_PASSWORD"
  fi
fi

# 1b: Long flag: --password=<plaintext> (any db client)
#     --password (alone) → OK (prompts).  --password=$VAR → OK.
if echo "$CMD" | grep -qE -- '--password=[^$[:space:]]'; then
  block "plaintext-password" \
        "Plaintext password in --password= flag" \
        "Use: --password=\$DB_PASSWORD"
fi

# 1c: Inline env: MYSQL_PWD=<plaintext> or PGPASSWORD=<plaintext>
#     MYSQL_PWD=$VAR → OK.  MYSQL_PWD=literal → BLOCK.
if echo "$CMD" | grep -qE '(MYSQL_PWD|PGPASSWORD)=[^$[:space:]]'; then
  block "plaintext-password" \
        "Plaintext password in environment variable assignment" \
        "Export the password in a separate, secured step"
fi

# ══════════════════════════════════════════════════════════════════════
# Rule 2: Block destructive/privilege SQL without approval stamp
# INSERT and CREATE are intentionally allowed (additive, lower risk).
# ══════════════════════════════════════════════════════════════════════

if echo "$CMD" | grep -qiE '\b(UPDATE|DELETE|DROP|TRUNCATE|ALTER|GRANT|REVOKE)\b'; then
  # Derive project name from git root (stable across subdirectories)
  PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  [ -z "$PROJECT" ] && PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
  STAMP="/tmp/${PROJECT}-db-write-approved"

  # Check stamp exists AND is less than 4 hours old
  if [ -f "$STAMP" ]; then
    STAMP_FRESH=$(find "$STAMP" -mmin -240 2>/dev/null)
    if [ -n "$STAMP_FRESH" ]; then
      echo "db-guard: destructive SQL allowed via $STAMP" >&2
      exit 0
    else
      echo "db-guard: approval stamp expired (>4h old), re-approve needed" >&2
    fi
  fi

  block "destructive-sql" \
        "Destructive SQL (UPDATE/DELETE/DROP/TRUNCATE/ALTER/GRANT/REVOKE) without approval" \
        "Read-only OK (SELECT/SHOW/DESCRIBE). For writes: touch $STAMP (4h TTL, human only)"
fi

# ── All checks passed ──
exit 0
