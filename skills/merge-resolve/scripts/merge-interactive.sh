#!/bin/bash
set -euo pipefail

# Colors
G='\033[32m' R='\033[31m' Y='\033[33m' C='\033[36m'
B='\033[1m' D='\033[2m' X='\033[0m'

FILE="${1:-}"
[[ -z "$FILE" ]] && { echo "Usage: merge-interactive.sh <file>"; exit 1; }
[[ -f "$FILE" ]] || { echo "File not found: $FILE"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

total=$(awk '/^<<<<<<</{n++} END{print n+0}' "$FILE")
[[ "$total" -eq 0 ]] && { echo "No conflicts in $FILE"; exit 0; }

# Extract each conflict's ours/theirs sections
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

awk -v dir="$tmpdir" '
  /^<<<<<<</ {
    n++; s="ours"
    ref=$0; sub(/^<<<<<<< */, "", ref)
    print ref > (dir "/c" n "_ours_ref")
    print NR > (dir "/c" n "_line")
    next
  }
  /^\|\|\|\|\|\|\|/ && s != "" { s="base"; next }
  /^=======/ && s != "" { s="theirs"; next }
  /^>>>>>>>/ && s != "" {
    ref=$0; sub(/^>>>>>>> */, "", ref)
    print ref > (dir "/c" n "_theirs_ref")
    s=""; next
  }
  s == "ours"   { print >> (dir "/c" n "_ours") }
  s == "theirs" { print >> (dir "/c" n "_theirs") }
' "$FILE"

# Header
echo ""
echo -e "${B}$FILE${X} — ${C}$total conflict(s)${X}"

# Walk through each conflict
decisions=()
for i in $(seq 1 "$total"); do
  line=$(cat "$tmpdir/c${i}_line" 2>/dev/null || echo "?")
  ours_ref=$(cat "$tmpdir/c${i}_ours_ref" 2>/dev/null || echo "HEAD")
  theirs_ref=$(cat "$tmpdir/c${i}_theirs_ref" 2>/dev/null || echo "incoming")

  echo -e "\n${D}─────────────────────────────────────${X}"
  echo -e "  ${B}[$i/$total]${X} line $line"

  echo -e "\n  ${G}▸ OURS (${ours_ref})${X}"
  if [[ -f "$tmpdir/c${i}_ours" ]]; then
    sed 's/^/    /' "$tmpdir/c${i}_ours"
  else
    echo -e "    ${D}(empty)${X}"
  fi

  echo -e "\n  ${R}▸ THEIRS (${theirs_ref})${X}"
  if [[ -f "$tmpdir/c${i}_theirs" ]]; then
    sed 's/^/    /' "$tmpdir/c${i}_theirs"
  else
    echo -e "    ${D}(empty)${X}"
  fi

  echo ""
  while true; do
    echo -ne "  ${C}(o)${X}urs  ${C}(t)${X}heirs  ${C}(b)${X}oth  ${C}(s)${X}kip: "
    read -n 1 -s choice
    case "$choice" in
      o|O) echo -e "${G}→ ours${X}";   decisions+=("o"); break ;;
      t|T) echo -e "${R}→ theirs${X}"; decisions+=("t"); break ;;
      b|B) echo -e "${Y}→ both${X}";   decisions+=("b"); break ;;
      s|S) echo -e "${D}→ skip${X}";   decisions+=("s"); break ;;
    esac
  done
done

echo -e "\n${D}─────────────────────────────────────${X}"

# Summary
echo -e "\n${B}Summary:${X}"
for i in $(seq 1 "$total"); do
  d="${decisions[$((i-1))]}"
  case "$d" in
    o) label="${G}ours${X}" ;;
    t) label="${R}theirs${X}" ;;
    b) label="${Y}both${X}" ;;
    s) label="${D}skip${X}" ;;
  esac
  echo -e "  #$i: $label"
done

echo ""
echo -ne "${B}Apply?${X} (y/n): "
read -n 1 -s confirm
echo ""

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

decision_str=$(IFS=,; echo "${decisions[*]}")
"$SCRIPT_DIR/merge-resolve.sh" batch "$FILE" "$decision_str"
