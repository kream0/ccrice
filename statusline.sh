#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PERCENT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

# Round percentage to integer
PERCENT_INT=$(printf "%.0f" "$PERCENT_USED")

# Color codes
CYAN='\033[36m'
YELLOW='\033[33m'
BLUE='\033[34m'
GREEN='\033[32m'
ORANGE='\033[38;5;208m'
RED='\033[31m'
RESET='\033[0m'

# Color context percentage based on usage
if [ "$PERCENT_INT" -lt 25 ]; then
    CTX_COLOR=$GREEN
elif [ "$PERCENT_INT" -lt 50 ]; then
    CTX_COLOR=$YELLOW
elif [ "$PERCENT_INT" -lt 75 ]; then
    CTX_COLOR=$ORANGE
else
    CTX_COLOR=$RED
fi

# Get git branch if in a repo
GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        GIT_BRANCH=" ${YELLOW}($BRANCH)${RESET}"
    fi
fi

# Output status line
echo -e "${CYAN}${CURRENT_DIR##*/}${RESET}${GIT_BRANCH} | ${BLUE}${MODEL_DISPLAY}${RESET} | ${CTX_COLOR}Context: ${PERCENT_INT}%${RESET}"
