#!/usr/bin/env bash
# Validate workspace config before launch
set -euo pipefail

project_dir="$HOME/AI/$WS_NAME"
config="$project_dir/.workspace.yaml"

if [[ ! -f "$config" ]]; then
  echo "  error: no .workspace.yaml found for $WS_NAME" >&2
  exit 1
fi

# Check required fields exist
if ! ruby -ryaml -e "
  data = YAML.safe_load(File.read('$config'))
  abort 'missing: name' unless data['name']
  abort 'missing: layout.panes' unless data.dig('layout', 'panes')
" 2>/dev/null; then
  echo "  error: invalid .workspace.yaml for $WS_NAME" >&2
  exit 1
fi
