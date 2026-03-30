#!/usr/bin/env bash
# Log workspace launches
set -euo pipefail

log_dir="$HOME/AI/.workspace/logs"
mkdir -p "$log_dir"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) launched $WS_NAME" >> "$log_dir/activity.log"
