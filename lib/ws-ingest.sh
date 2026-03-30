#!/usr/bin/env bash
# ws-ingest.sh — CLI-side ingest orchestration
#
# Validates config, runs Linear data fetch, guides user to the skill for full research.

WS_INGEST_SCRIPT="$WS_SYSTEM/plugins/ws-ingest/bin/linear-fetch.sh"

ws_ingest() {
  local name="" linear_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --linear-only) linear_only=true; shift ;;
      -*)            ws_die "Unknown flag: $1. Usage: ws ingest <name> [--linear-only]" ;;
      *)             name="$1"; shift ;;
    esac
  done

  [[ -z "$name" ]] && ws_die "Usage: ws ingest <name> [--linear-only]"

  local project_dir config
  project_dir=$(ws_project_dir "$name")
  config=$(ws_config_path "$name")

  [[ -d "$project_dir" ]] || ws_die "Project not found: $name"
  [[ -f "$config" ]] || ws_die "No .workspace.yaml: $name"

  # Source .env if present (same as Flox does)
  if [[ -f "$project_dir/.env" ]]; then
    set -a; source "$project_dir/.env"; set +a
  fi

  local config_json
  config_json=$(ws_yaml_to_json "$config")

  local linear_project_id
  linear_project_id=$(echo "$config_json" | jq -r '.ingest.linear_project_id // empty')

  local template
  template=$(echo "$config_json" | jq -r '.template // "research"')

  echo ""
  echo "  Workspace: $name (template: $template)"

  # Linear fetch
  if [[ -n "$linear_project_id" ]]; then
    ws_ingest_linear "$name" "$linear_project_id" "$project_dir"
  else
    echo "  Linear: no project_id configured (skipping)"
  fi

  if [[ "$linear_only" == true ]]; then
    echo ""
    return 0
  fi

  # Guide user to full ingest
  echo ""
  echo "  For full ingest (web research + synthesis), run in Claude Code:"
  echo ""
  echo "    /ws-ingest:ingest"
  echo ""
}

ws_ingest_linear() {
  local name="$1" project_id="$2" project_dir="$3"

  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    echo ""
    echo "  Linear project linked ($project_id) but LINEAR_API_KEY not set."
    echo "  Add to $project_dir/.env:"
    echo ""
    echo "    LINEAR_API_KEY=lin_api_xxxxx"
    echo ""
    return 1
  fi

  echo "  Linear: fetching project $project_id..."

  local output_dir="$project_dir/data/linear"
  local manifest
  manifest=$("$WS_INGEST_SCRIPT" \
    --project-id "$project_id" \
    --output-dir "$output_dir" 2>&1 | tee /dev/stderr | tail -1)

  # Log to journal
  local issues_count docs_count
  issues_count=$(echo "$manifest" | jq -r '.issues_count // 0' 2>/dev/null || echo "0")
  docs_count=$(echo "$manifest" | jq -r '.documents_count // 0' 2>/dev/null || echo "0")

  source "$WS_SYSTEM/lib/ws-journal.sh"
  ws_journal_append "$name" "note" "Linear data fetched: $issues_count issues, $docs_count documents (project: $project_id)"

  echo "  Linear: done ($issues_count issues, $docs_count documents)"
}
