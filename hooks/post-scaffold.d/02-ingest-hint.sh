#!/usr/bin/env bash
set -euo pipefail

project_dir="$HOME/AI/$WS_NAME"
config="$project_dir/.workspace.yaml"

template=$(ruby -ryaml -e "puts YAML.safe_load(File.read('$config'))['template'] rescue ''" 2>/dev/null)

case "$template" in
  deal-war-room|theme-research|research)
    echo ""
    echo "  Tip: Edit .workspace.yaml to configure ingest settings,"
    echo "  then run /ws-ingest:ingest in Claude Code to seed data."
    ;;
esac
