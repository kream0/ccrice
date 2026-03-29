#!/bin/bash
# Test suite for project-db-guard.sh
# Tests all rules with exact incident patterns and edge cases.

HOOK="/home/karimel/ccrice/templates/hooks/project-db-guard.sh"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

test_case() {
  local desc="$1"
  local expected_exit="$2"
  local cmd="$3"
  ((TOTAL++))

  # Build JSON input — use jq to safely escape the command string
  local json
  json=$(jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')

  local stderr_out
  stderr_out=$(echo "$json" | bash "$HOOK" 2>&1 >/dev/null)
  local actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected exit $expected_exit, got $actual_exit)"
    [ -n "$stderr_out" ] && echo "        stderr: $stderr_out"
    ((FAIL++))
  fi
}

test_non_bash() {
  local desc="$1"
  local expected_exit="$2"
  local json="$3"
  ((TOTAL++))

  local actual_exit
  echo "$json" | bash "$HOOK" > /dev/null 2>&1
  actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    ((PASS++))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++))
  fi
}

# ── Stamp setup ──
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
[ -z "$PROJECT" ] && PROJECT=$(basename "$(pwd)")
STAMP="/tmp/${PROJECT}-db-write-approved"
rm -f "$STAMP"

echo -e "${CYAN}══════ Rule 0: Anti-self-approval ══════${NC}"
test_case "BLOCK: touch stamp"                    2 "touch $STAMP"
test_case "BLOCK: touch with path"                2 "touch /tmp/${PROJECT}-db-write-approved"
test_case "BLOCK: echo > stamp"                   2 "echo approved > /tmp/${PROJECT}-db-write-approved"
test_case "BLOCK: tee stamp"                      2 "echo ok | tee /tmp/${PROJECT}-db-write-approved"
test_case "BLOCK: cp to stamp"                    2 "cp /dev/null /tmp/${PROJECT}-db-write-approved"
test_case "ALLOW: rm stamp (removal is fine)"     0 "rm /tmp/${PROJECT}-db-write-approved"
test_case "ALLOW: ls stamp (read is fine)"        0 "ls -la /tmp/${PROJECT}-db-write-approved"
test_case "ALLOW: cat stamp (read is fine)"       0 "cat /tmp/${PROJECT}-db-write-approved"

echo ""
echo -e "${CYAN}══════ Rule 1a: mysql -p plaintext password ══════${NC}"
test_case "BLOCK: mysql -pyelimoov_pass_2026"      2 'mysql -u yelimoov -pyelimoov_pass_2026 yelimoov_db -e "SELECT 1"'
test_case "BLOCK: mysql -proot"                     2 'mysql -u root -proot test_db'
test_case "BLOCK: mysql -pMyP@ss123"                2 'mysql -u admin -pMyP@ss123 -e "SHOW TABLES"'
test_case "BLOCK: mysqldump -proot"                 2 'mysqldump -u root -proot test_db > dump.sql'
test_case "BLOCK: mysqladmin -psecret"              2 'mysqladmin -u root -psecret status'
test_case "ALLOW: mysql -p (prompt mode)"           0 'mysql -u root -p test_db'
test_case 'ALLOW: mysql -p$DB_PASS'                 0 'mysql -u root -p$DB_PASS test_db'
test_case 'ALLOW: mysql -p${DB_PASS}'               0 'mysql -u root -p${DB_PASS} test_db'
test_case 'ALLOW: mysql -p"$DB_PASS"'               0 'mysql -u root -p"$DB_PASS" test_db'

echo ""
echo -e "${CYAN}══════ Rule 1b: --password= plaintext ══════${NC}"
test_case "BLOCK: mysql --password=secret"          2 'mysql -u root --password=secret test_db'
test_case "BLOCK: mysql --password=MyP@ss!"         2 'mysql --password=MyP@ss! -u root'
test_case "BLOCK: psql --password=secret"           2 'psql -U user --password=secret'
test_case 'ALLOW: mysql --password=$DB_PASS'        0 'mysql -u root --password=$DB_PASS test_db'
test_case 'ALLOW: mysql --password=${DB_PASS}'      0 'mysql --password=${DB_PASS} -u root'
test_case "ALLOW: psql --password (prompt)"         0 'psql -U user --password'
test_case "ALLOW: mysql --password= (empty)"        0 'mysql -u root --password= test_db'

echo ""
echo -e "${CYAN}══════ Rule 1c: MYSQL_PWD/PGPASSWORD plaintext ══════${NC}"
test_case "BLOCK: MYSQL_PWD=secret"                 2 'MYSQL_PWD=secret mysql -u root test_db'
test_case "BLOCK: PGPASSWORD=secret"                2 'PGPASSWORD=secret psql -U user test_db'
test_case "BLOCK: PGPASSWORD=mypass123"             2 'PGPASSWORD=mypass123 psql -U admin -c "SELECT 1"'
test_case 'ALLOW: MYSQL_PWD=$DB_PASS'              0 'MYSQL_PWD=$DB_PASS mysql -u root test_db'
test_case 'ALLOW: PGPASSWORD=$PG_PASS'             0 'PGPASSWORD=$PG_PASS psql -U user test_db'

echo ""
echo -e "${CYAN}══════ Rule 2: Destructive SQL (no stamp) ══════${NC}"
rm -f "$STAMP"

test_case "BLOCK: UPDATE"     2 'mysql -u root -p$DB_PASS -e "UPDATE users SET password='\''new'\'' WHERE id=1"'
test_case "BLOCK: DELETE"     2 'mysql -u root -p$DB_PASS -e "DELETE FROM sessions WHERE expired=1"'
test_case "BLOCK: DROP"       2 'mysql -u root -p$DB_PASS -e "DROP TABLE temp_data"'
test_case "BLOCK: TRUNCATE"   2 'mysql -u root -p$DB_PASS -e "TRUNCATE TABLE logs"'
test_case "BLOCK: ALTER"      2 'mysql -u root -p$DB_PASS -e "ALTER TABLE users ADD COLUMN age INT"'
test_case "BLOCK: GRANT"      2 'mysql -u root -p$DB_PASS -e "GRANT ALL ON *.* TO '\''agent'\''@'\''%'\''"'
test_case "BLOCK: REVOKE"     2 'mysql -u root -p$DB_PASS -e "REVOKE ALL ON *.* FROM '\''agent'\''@'\''%'\''"'
test_case "BLOCK: update (lowercase)" 2 'psql -U user -c "update users set name='\''x'\''"'
test_case "BLOCK: drop (mixed case)"  2 'sqlite3 app.db "Drop Table users"'
test_case "BLOCK: piped DELETE"       2 'echo "DELETE FROM users WHERE id=5" | mysql -u root -p$DB_PASS'
test_case "ALLOW: SELECT"    0 'mysql -u root -p$DB_PASS -e "SELECT * FROM users"'
test_case "ALLOW: SHOW"      0 'mysql -u root -p$DB_PASS -e "SHOW TABLES"'
test_case "ALLOW: DESCRIBE"  0 'mysql -u root -p$DB_PASS -e "DESCRIBE users"'
test_case "ALLOW: show databases" 0 'mysql -u root -p$DB_PASS -e "show databases"'
test_case "ALLOW: INSERT (additive)" 0 'mysql -u root -p$DB_PASS -e "INSERT INTO logs VALUES (1, '\''test'\'')"'
test_case "ALLOW: CREATE TABLE"      0 'mysql -u root -p$DB_PASS -e "CREATE TABLE temp (id INT)"'

echo ""
echo -e "${CYAN}══════ Rule 2: Approval stamp override ══════${NC}"
touch "$STAMP"
test_case "ALLOW: UPDATE with stamp"   0 'mysql -u root -p$DB_PASS -e "UPDATE users SET name='\''test'\''"'
test_case "ALLOW: DELETE with stamp"   0 'mysql -u root -p$DB_PASS -e "DELETE FROM sessions"'
test_case "ALLOW: DROP with stamp"     0 'mysql -u root -p$DB_PASS -e "DROP TABLE temp"'
test_case "ALLOW: GRANT with stamp"    0 'mysql -u root -p$DB_PASS -e "GRANT SELECT ON db.* TO '\''ro'\''@'\''%'\''"'
test_case "BLOCK: plaintext pw IGNORES stamp" 2 'mysql -u root -psecret -e "UPDATE users SET x=1"'
rm -f "$STAMP"

echo ""
echo -e "${CYAN}══════ Rule 2: Expired stamp (>4h old) ══════${NC}"
touch -t "$(date -d '5 hours ago' '+%Y%m%d%H%M.%S')" "$STAMP"
test_case "BLOCK: UPDATE with expired stamp" 2 'mysql -u root -p$DB_PASS -e "UPDATE users SET x=1"'
rm -f "$STAMP"

echo ""
echo -e "${CYAN}══════ Edge cases ══════${NC}"
test_case "ALLOW: non-db command (ls)"          0 'ls -la'
test_case "ALLOW: non-db command (git)"         0 'git status'
test_case "ALLOW: npm install mysql2"           0 'npm install mysql2'
test_case "ALLOW: grep in mysql log"            0 'grep "UPDATE" /var/log/mysql.log'
test_case "ALLOW: cat /etc/mysql/my.cnf"        0 'cat /etc/mysql/my.cnf'
test_case "ALLOW: psql -p 5432 (port flag)"     0 'psql -p 5432 -U user -c "SELECT 1"'
test_case "ALLOW: psql -p5432 (port, no space)" 0 'psql -p5432 -U user -c "SELECT 1"'
test_non_bash "ALLOW: non-Bash tool (Edit)"     0 '{"tool_name":"Edit","tool_input":{"command":"mysql -proot"}}'
test_non_bash "ALLOW: non-Bash tool (Read)"     0 '{"tool_name":"Read","tool_input":{"command":"DROP TABLE x"}}'
test_case "BLOCK: ssh + mysql -pplaintext"      2 'ssh server "mysql -u root -proot -e \"SELECT 1\""'
test_case "BLOCK: ssh + mysql DROP"             2 'ssh server "mysql -u root -p\$PASS -e \"DROP TABLE x\""'
test_case "BLOCK: heredoc with DROP"            2 'mysql -u root -p$DB_PASS <<EOF
DROP TABLE users;
EOF'

echo ""
echo -e "${CYAN}══════ Exact incident replay (yeli-moov) ══════${NC}"
test_case "INCIDENT: plaintext pass + SELECT"   2 'mysql -u yelimoov -pyelimoov_pass_2026 yelimoov_db -e "SELECT * FROM users"'
test_case "INCIDENT: env var + UPDATE password"  2 'mysql -u yelimoov -p$DB_PASS yelimoov_db -e "UPDATE users SET password='\''newpass'\'' WHERE email='\''user@test.com'\''"'
test_case "INCIDENT: env var + DELETE"           2 'mysql -u yelimoov -p$DB_PASS yelimoov_db -e "DELETE FROM users WHERE id=99"'
test_case "INCIDENT: env var + DROP"             2 'mysql -u yelimoov -p$DB_PASS yelimoov_db -e "DROP DATABASE yelimoov_db"'

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} (of $TOTAL)"
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
else
  echo -e "${RED}SOME TESTS FAILED${NC}"
fi
exit $FAIL
