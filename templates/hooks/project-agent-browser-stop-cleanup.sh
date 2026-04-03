#!/bin/bash
# Hook: Stop — Clean up all Chrome processes when session ends
# This prevents orphaned Chrome from accumulating across session rotations.
set -euo pipefail

# Run full cleanup unconditionally
/home/karimel/fang/display/fang-chrome-cleanup >/dev/null 2>&1 || true
exit 0
