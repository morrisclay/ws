#!/usr/bin/env bash
# Warn about uncommitted changes before stopping
set -euo pipefail

project_dir="$HOME/AI/$WS_NAME"

if [[ -d "$project_dir/.git" ]]; then
  if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
     ! git -C "$project_dir" diff --cached --quiet 2>/dev/null; then
    echo "  warn: $WS_NAME has uncommitted changes"
  fi
fi
