#!/bin/bash
set -euo pipefail

CMD="${1:-help}"
FILE="${2:-}"
NUM="${3:-all}"

usage() {
  cat <<'EOF'
Usage:
  merge-resolve.sh list                  List files with conflicts
  merge-resolve.sh show   <file> [N]    Show conflict(s), numbered
  merge-resolve.sh ours   <file> [N]    Keep HEAD side
  merge-resolve.sh theirs <file> [N]    Keep incoming side
  merge-resolve.sh both   <file> [N]    Keep both sides concatenated
EOF
}

require_file() {
  [[ -z "$FILE" ]] && { usage; exit 1; }
  [[ -f "$FILE" ]] || { echo "File not found: $FILE"; exit 1; }
}

count_conflicts() {
  awk '/^<<<<<<</{n++} END{print n+0}' "$1"
}

case "$CMD" in
  list)
    git diff --name-only --diff-filter=U 2>/dev/null \
      || grep -rl '^<<<<<<< ' . 2>/dev/null \
      || echo "No conflicts found."
    ;;

  show)
    require_file
    total=$(count_conflicts "$FILE")
    if [[ "$total" -eq 0 ]]; then
      echo "No conflicts in $FILE"
      exit 0
    fi
    awk -v target="$NUM" '
      /^<<<<<<</ {
        n++
        if (target == "all" || n == int(target)) {
          show = 1
          printf "\n=== Conflict %d (line %d) ===\n", n, NR
        }
      }
      show { print }
      /^>>>>>>>/ && show { show = 0 }
    ' "$FILE"
    echo ""
    echo "$total conflict(s) in $FILE"
    ;;

  ours|theirs|both)
    require_file
    before=$(count_conflicts "$FILE")
    [[ "$before" -eq 0 ]] && { echo "No conflicts in $FILE"; exit 0; }
    if [[ "$NUM" != "all" ]] && [[ "$NUM" -gt "$before" ]]; then
      echo "Conflict #$NUM does not exist ($before total)"
      exit 1
    fi

    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    awk -v action="$CMD" -v target="$NUM" '
      BEGIN { n = 0; state = "normal" }

      /^<<<<<<</ {
        n++
        if (target == "all" || n == int(target)) {
          state = (action == "theirs") ? "skip" : "keep"
          next
        }
        print; next
      }

      # diff3 base section marker
      /^\|\|\|\|\|\|\|/ && state != "normal" {
        state = "skip"
        next
      }

      /^=======/ && state != "normal" {
        if (action == "ours") state = "skip"
        else state = "keep"
        next
      }

      /^>>>>>>>/ && state != "normal" {
        state = "normal"
        next
      }

      state == "skip" { next }

      { print }
    ' "$FILE" > "$tmp"

    mv "$tmp" "$FILE"

    after=$(count_conflicts "$FILE")
    resolved=$(( before - after ))
    label=$( [[ "$NUM" == "all" ]] && echo "all" || echo "#$NUM" )
    echo "Resolved $label ($CMD) in $FILE — $resolved fixed, $after remaining"
    ;;

  *)
    usage
    ;;
esac
