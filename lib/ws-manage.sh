#!/usr/bin/env bash
# ws-manage.sh — list, stop, edit, worktree commands

source "$WS_SYSTEM/hooks/run-hooks.sh"

ws_list() {
  echo ""
  printf "  %-25s %-18s %-8s\n" "PROJECT" "TEMPLATE" "STATUS"
  printf "  %-25s %-18s %-8s\n" "───────" "────────" "──────"

  local found=0
  for dir in "$WS_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name=$(basename "$dir")
    [[ "$name" == .* ]] && continue

    local config="$dir/.workspace.yaml"
    if [[ -f "$config" ]]; then
      found=1
      local template status
      template=$(ws_yaml_get "$config" "template" 2>/dev/null || echo "custom")

      if [[ -f "$dir/.workspace.lock" ]]; then
        local lock_uuid
        lock_uuid=$(cat "$dir/.workspace.lock")
        if "$CMUX" --json list-workspaces 2>/dev/null | jq -e ".workspaces[] | select(.ref == \"$lock_uuid\" or .title == \"$name\")" >/dev/null 2>&1; then
          status="running"
        else
          rm -f "$dir/.workspace.lock"
          status="stopped"
        fi
      else
        status="stopped"
      fi
      printf "  %-25s %-18s %-8s\n" "$name" "$template" "$status"
    fi
  done

  # Also list registered external workspaces
  local registry="$WS_SYSTEM/registry.jsonl"
  if [[ -f "$registry" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ext_path ext_name ext_template
      ext_path=$(echo "$line" | jq -r '.path' 2>/dev/null)
      ext_name=$(echo "$line" | jq -r '.name' 2>/dev/null)
      ext_template=$(echo "$line" | jq -r '.template // "generic"' 2>/dev/null)

      # Verify the workspace still exists
      if [[ -d "$ext_path" && -f "$ext_path/.workspace.yaml" ]]; then
        found=1
        local status="stopped"
        if [[ -f "$ext_path/.workspace.lock" ]]; then
          status="active"
        fi
        printf "  %-25s %-18s %-8s  %s\n" "$ext_name" "$ext_template" "$status" "$ext_path"
      fi
    done < "$registry"
  fi

  if [[ $found -eq 0 ]]; then
    echo "  No projects found. Create one with: ws new <name> --template=<type>"
    echo "  Or initialize current dir with: ws init"
  fi
  echo ""
}

ws_stop() {
  local name="$1"
  [[ -z "$name" ]] && ws_die "Usage: ws stop <name>"

  local project_dir
  project_dir=$(ws_project_dir "$name")
  [[ -d "$project_dir" ]] || ws_die "Project not found: $name"

  local ws_ref
  ws_ref=$(ws_is_running "$name")

  if [[ -z "$ws_ref" && -f "$project_dir/.workspace.lock" ]]; then
    local lock_uuid
    lock_uuid=$(cat "$project_dir/.workspace.lock")
    # Try the lock UUID directly
    if "$CMUX" --json list-workspaces 2>/dev/null | jq -e ".workspaces[] | select(.ref == \"$lock_uuid\")" >/dev/null 2>&1; then
      ws_ref="$lock_uuid"
    fi
  fi

  if [[ -n "$ws_ref" ]]; then
    ws_run_hooks "pre-stop" "$name" "$ws_ref"
    "$CMUX" close-workspace --workspace "$ws_ref" 2>/dev/null || true
    rm -f "$project_dir/.workspace.lock"
    ws_run_hooks "post-stop" "$name"
    echo "  Workspace stopped: $name"
  else
    rm -f "$project_dir/.workspace.lock"
    echo "  Workspace not running: $name"
  fi
}

ws_edit() {
  local name="$1"
  [[ -z "$name" ]] && ws_die "Usage: ws edit <name>"

  local config
  config=$(ws_config_path "$name")
  [[ -f "$config" ]] || ws_die "No .workspace.yaml found for: $name"

  ${EDITOR:-vim} "$config"
}

ws_delete() {
  local name="" force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force=true; shift ;;
      -*)         ws_die "Unknown flag: $1" ;;
      *)          name="$1"; shift ;;
    esac
  done

  [[ -z "$name" ]] && ws_die "Usage: ws delete <name> [--force]"

  local project_dir
  project_dir=$(ws_project_dir "$name")
  [[ -d "$project_dir" ]] || ws_die "Project not found: $name"

  # Stop if running
  local ws_ref
  ws_ref=$(ws_is_running "$name" 2>/dev/null || true)
  if [[ -z "$ws_ref" && -f "$project_dir/.workspace.lock" ]]; then
    local lock_uuid
    lock_uuid=$(cat "$project_dir/.workspace.lock")
    if "$CMUX" --json list-workspaces 2>/dev/null | jq -e ".workspaces[] | select(.ref == \"$lock_uuid\")" >/dev/null 2>&1; then
      ws_ref="$lock_uuid"
    fi
  fi

  if [[ -n "$ws_ref" ]]; then
    if [[ "$force" != true ]]; then
      ws_die "Workspace is running. Stop it first (ws stop $name) or use --force"
    fi
    ws_run_hooks "pre-stop" "$name" "$ws_ref"
    "$CMUX" close-workspace --workspace "$ws_ref" 2>/dev/null || true
    ws_run_hooks "post-stop" "$name"
  fi

  # Check for uncommitted changes
  if [[ "$force" != true && -d "$project_dir/.git" ]]; then
    if ! git -C "$project_dir" diff --quiet 2>/dev/null || \
       ! git -C "$project_dir" diff --cached --quiet 2>/dev/null; then
      ws_die "$name has uncommitted changes. Use --force to delete anyway"
    fi
  fi

  # Confirmation prompt (skip with --force)
  if [[ "$force" != true ]]; then
    printf "  Delete workspace '%s' and all its files? [y/N] " "$name"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Cancelled."; return 0; }
  fi

  # Clean up worktrees
  for wt in "$WS_ROOT/.worktrees/${name}--"*; do
    if [[ -d "$wt" ]]; then
      git -C "$project_dir" worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
    fi
  done

  # Delete the project
  rm -rf "$project_dir"

  echo "  Workspace deleted: $name"
}

ws_worktree() {
  local name="$1" branch="$2"
  [[ -z "$name" || -z "$branch" ]] && ws_die "Usage: ws worktree <name> <branch>"

  local project_dir worktree_dir
  project_dir=$(ws_resolve_project_dir "$name" 2>/dev/null) \
    || project_dir=$(ws_project_dir "$name")
  [[ -d "$project_dir" ]] || ws_die "Project not found: $name"
  [[ -d "$project_dir/.git" ]] || ws_die "Not a git repo: $name"

  # Determine worktree location based on workspace type
  local standalone="false"
  if [[ -f "$project_dir/.workspace.yaml" ]]; then
    standalone=$(ws_yaml_get "$project_dir/.workspace.yaml" "standalone" 2>/dev/null || echo "false")
  fi

  if [[ "$standalone" == "true" ]]; then
    worktree_dir="$project_dir/.worktrees/${branch}"
    mkdir -p "$project_dir/.worktrees"
  else
    worktree_dir="$WS_ROOT/.worktrees/${name}--${branch}"
  fi

  if [[ -d "$worktree_dir" ]]; then
    echo "  Worktree already exists: $worktree_dir"
    return 0
  fi

  # Use lockf for concurrency safety
  local lockfile="$project_dir/.worktree.lock"
  /usr/bin/lockf -k "$lockfile" \
    git -C "$project_dir" worktree add "$worktree_dir" -b "$branch" 2>/dev/null \
    || /usr/bin/lockf -k "$lockfile" \
      git -C "$project_dir" worktree add "$worktree_dir" "$branch"

  echo "  Worktree created: $worktree_dir"
  echo "  Branch: $branch"
}
