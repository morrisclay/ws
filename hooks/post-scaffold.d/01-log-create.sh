#!/usr/bin/env bash
# Log workspace creation
set -euo pipefail

log_dir="$HOME/AI/.workspace/logs"
mkdir -p "$log_dir"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) created $WS_NAME" >> "$log_dir/activity.log"
