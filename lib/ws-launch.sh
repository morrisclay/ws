#!/usr/bin/env bash
# ws-launch.sh — Launch flow orchestration

source "$WS_SYSTEM/hooks/run-hooks.sh"

ws_launch() {
  local name="$1"
  [[ -z "$name" ]] && ws_die "Usage: ws <name>"

  local project_dir
  project_dir=$(ws_project_dir "$name")
  [[ -d "$project_dir" ]] || ws_die "Project not found: $name. Create with: ws new $name"

  local config
  config=$(ws_config_path "$name")
  [[ -f "$config" ]] || ws_die "No .workspace.yaml found in $name. Create with: ws new $name"

  ws_require_cmux

  # --- 0. Pre-launch hooks ---
  ws_run_hooks "pre-launch" "$name"

  # --- 1. Check if already running ---
  local existing_ref
  existing_ref=$(ws_is_running "$name")
  if [[ -n "$existing_ref" ]]; then
    "$CMUX" select-workspace --workspace "$existing_ref"
    echo "  Switched to existing workspace: $name"
    return 0
  fi

  # Also check lock file
  if [[ -f "$project_dir/.workspace.lock" ]]; then
    local lock_ref
    lock_ref=$(cat "$project_dir/.workspace.lock")
    if "$CMUX" --json list-workspaces 2>/dev/null | jq -e ".workspaces[] | select(.ref == \"$lock_ref\")" >/dev/null 2>&1; then
      "$CMUX" select-workspace --workspace "$lock_ref"
      echo "  Switched to existing workspace: $name"
      return 0
    else
      rm -f "$project_dir/.workspace.lock"
    fi
  fi

  # --- 2. Parse config ---
  local config_json
  config_json=$(ws_yaml_to_json "$config")
  [[ -z "$config_json" ]] && ws_die "Failed to parse .workspace.yaml"

  local display_name
  display_name=$(echo "$config_json" | jq -r '.name // "'"$name"'"')

  echo "  Launching workspace: $display_name"

  # --- 3. Create workspace ---
  # cmux new-workspace returns "OK <UUID>" not JSON
  local ws_create_output ws_uuid ws_ref
  ws_create_output=$("$CMUX" new-workspace 2>&1)
  ws_uuid=$(echo "$ws_create_output" | awk '{print $2}')

  if [[ -z "$ws_uuid" ]]; then
    ws_die "Failed to create cmux workspace: $ws_create_output"
  fi

  # Find the workspace ref by UUID using --id-format both
  ws_ref=$("$CMUX" --json --id-format both list-workspaces 2>/dev/null \
    | jq -r ".workspaces[] | select(.id == \"$ws_uuid\") | .ref" 2>/dev/null)

  if [[ -z "$ws_ref" || "$ws_ref" == "null" ]]; then
    # Fallback: use the UUID directly (cmux accepts UUIDs as refs)
    ws_ref="$ws_uuid"
  fi

  "$CMUX" rename-workspace --workspace "$ws_ref" "$name"
  "$CMUX" select-workspace --workspace "$ws_ref"
  ws_set_progress "$ws_ref" "0.1" "Launching $display_name..."

  # --- 4. Build layout ---
  # Get initial pane and surface (refs are global, not per-workspace)
  local panes_json initial_pane initial_surface
  panes_json=$("$CMUX" --json list-panes --workspace "$ws_ref" 2>&1)
  initial_pane=$(echo "$panes_json" | jq -r '.panes[0].ref')
  initial_surface=$(echo "$panes_json" | jq -r '.panes[0].surface_refs[0]')

  # Associative arrays for tracking refs
  declare -A pane_refs
  declare -A surface_refs
  declare -A pane_first_surface

  local pane_count
  pane_count=$(echo "$config_json" | jq '.layout.panes | length')

  for ((i = 0; i < pane_count; i++)); do
    local pane_json pane_name pane_dir split_from_name
    pane_json=$(echo "$config_json" | jq ".layout.panes[$i]")
    pane_name=$(echo "$pane_json" | jq -r '.name')
    pane_dir=$(echo "$pane_json" | jq -r '.direction // "null"')
    split_from_name=$(echo "$pane_json" | jq -r '.split_from // "null"')

    local current_pane_ref first_surface_ref

    if [[ "$pane_dir" == "null" ]]; then
      # First pane — use the initial one that comes with the workspace
      current_pane_ref="$initial_pane"
      first_surface_ref="$initial_surface"
      pane_refs["$pane_name"]="$initial_pane"
      pane_first_surface["$pane_name"]="$initial_surface"

      # Rename the initial surface tab
      local first_sname
      first_sname=$(echo "$pane_json" | jq -r '.surfaces[0].name')
      surface_refs["$first_sname"]="$initial_surface"
      "$CMUX" rename-tab --surface "$initial_surface" --workspace "$ws_ref" "$first_sname" 2>/dev/null || true
    else
      # Determine which surface to split from
      local split_surface
      if [[ "$split_from_name" != "null" && -n "${pane_first_surface[$split_from_name]:-}" ]]; then
        split_surface="${pane_first_surface[$split_from_name]}"
      else
        # Default: split from the previous pane's first surface
        local prev_idx=$((i - 1))
        local prev_name
        prev_name=$(echo "$config_json" | jq -r ".layout.panes[$prev_idx].name")
        split_surface="${pane_first_surface[$prev_name]:-$initial_surface}"
      fi

      # Determine first surface type
      local first_stype first_surl
      first_stype=$(echo "$pane_json" | jq -r '.surfaces[0].type // "terminal"')
      first_surl=$(echo "$pane_json" | jq -r '.surfaces[0].url // empty')

      # Create the split/pane
      local split_result
      if [[ "$first_stype" == "browser" ]]; then
        # Browser panes use new-pane (new-split only creates terminals)
        local pane_args=(--type browser --direction "$pane_dir" --workspace "$ws_ref")
        [[ -n "$first_surl" ]] && pane_args+=(--url "$first_surl")
        split_result=$("$CMUX" --json new-pane "${pane_args[@]}" 2>&1)
      else
        split_result=$("$CMUX" --json new-split "$pane_dir" \
          --surface "$split_surface" --workspace "$ws_ref" 2>&1)
      fi

      current_pane_ref=$(echo "$split_result" | jq -r '.pane_ref' 2>/dev/null)
      first_surface_ref=$(echo "$split_result" | jq -r '.surface_ref' 2>/dev/null)

      # Fallback: query the pane list for the newest pane
      if [[ -z "$current_pane_ref" || "$current_pane_ref" == "null" ]]; then
        local updated_panes
        updated_panes=$("$CMUX" --json list-panes --workspace "$ws_ref" 2>&1)
        current_pane_ref=$(echo "$updated_panes" | jq -r '.panes[-1].ref')
        first_surface_ref=$(echo "$updated_panes" | jq -r '.panes[-1].surface_refs[0]')
      fi

      pane_refs["$pane_name"]="$current_pane_ref"
      pane_first_surface["$pane_name"]="$first_surface_ref"

      local first_sname
      first_sname=$(echo "$pane_json" | jq -r '.surfaces[0].name')
      surface_refs["$first_sname"]="$first_surface_ref"
      "$CMUX" rename-tab --surface "$first_surface_ref" --workspace "$ws_ref" "$first_sname" 2>/dev/null || true
    fi

    # Create additional surfaces (tabs) within this pane — index > 0
    local surface_count
    surface_count=$(echo "$pane_json" | jq '.surfaces | length')

    for ((s = 1; s < surface_count; s++)); do
      local sj sname stype surl
      sj=$(echo "$pane_json" | jq ".surfaces[$s]")
      sname=$(echo "$sj" | jq -r '.name')
      stype=$(echo "$sj" | jq -r '.type // "terminal"')
      surl=$(echo "$sj" | jq -r '.url // empty')

      local surf_args=(--type "$stype" --pane "$current_pane_ref" --workspace "$ws_ref")
      [[ -n "$surl" ]] && surf_args+=(--url "$surl")

      local surf_result sref
      surf_result=$("$CMUX" --json new-surface "${surf_args[@]}" 2>&1)
      sref=$(echo "$surf_result" | jq -r '.surface_ref' 2>/dev/null)

      if [[ -z "$sref" || "$sref" == "null" ]]; then
        # Fallback: get newest surface in this pane
        sref=$("$CMUX" --json list-pane-surfaces --workspace "$ws_ref" --pane "$current_pane_ref" \
          | jq -r '.surfaces[-1].ref' 2>/dev/null)
      fi

      if [[ -n "$sref" && "$sref" != "null" ]]; then
        surface_refs["$sname"]="$sref"
        "$CMUX" rename-tab --surface "$sref" --workspace "$ws_ref" "$sname" 2>/dev/null || true
      fi
    done
  done

  ws_set_progress "$ws_ref" "0.4" "Activating environment..."
  ws_log "$ws_ref" "Layout created with $pane_count panes"

  # --- 5. Activate flox + send commands (parallel) ---
  local pids=()

  for ((i = 0; i < pane_count; i++)); do
    local pane_json surface_count
    pane_json=$(echo "$config_json" | jq ".layout.panes[$i]")
    surface_count=$(echo "$pane_json" | jq '.surfaces | length')

    for ((s = 0; s < surface_count; s++)); do
      local sj sname stype activate_flox cmd
      sj=$(echo "$pane_json" | jq ".surfaces[$s]")
      sname=$(echo "$sj" | jq -r '.name')
      stype=$(echo "$sj" | jq -r '.type // "terminal"')

      [[ "$stype" != "terminal" ]] && continue

      activate_flox=$(echo "$sj" | jq -r '.activate_flox // true')
      cmd=$(echo "$sj" | jq -r '.command // empty')
      local sref="${surface_refs[$sname]:-}"

      [[ -z "$sref" || "$sref" == "null" ]] && continue

      (
        # cd to project dir
        "$CMUX" send --workspace "$ws_ref" --surface "$sref" "cd $project_dir\n"
        sleep 0.3

        # Activate flox
        if [[ "$activate_flox" == "true" ]]; then
          "$CMUX" send --workspace "$ws_ref" --surface "$sref" "flox activate\n"
          sleep 1.5
        fi

        # Send command if any
        if [[ -n "$cmd" ]]; then
          "$CMUX" send --workspace "$ws_ref" --surface "$sref" "${cmd}\n"
        fi
      ) &
      pids+=($!)
    done
  done

  # Wait for all activations
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  ws_set_progress "$ws_ref" "0.7" "Environment ready"

  # --- 6. Wait for services ---
  local service_count
  service_count=$(echo "$config_json" | jq '.services // [] | length')

  for ((i = 0; i < service_count; i++)); do
    local svc_json svc_name svc_port svc_timeout svc_url
    svc_json=$(echo "$config_json" | jq ".services[$i]")
    svc_name=$(echo "$svc_json" | jq -r '.name')
    svc_port=$(echo "$svc_json" | jq -r '.port')
    svc_timeout=$(echo "$svc_json" | jq -r '.timeout // 30')
    svc_url=$(echo "$svc_json" | jq -r '.url // empty')

    ws_set_status "$ws_ref" "svc:$svc_name" "waiting for :$svc_port" "clock" ""

    local elapsed=0
    while ! nc -z localhost "$svc_port" 2>/dev/null && (( elapsed < svc_timeout )); do
      sleep 1
      elapsed=$((elapsed + 1))
    done

    if nc -z localhost "$svc_port" 2>/dev/null; then
      ws_set_status "$ws_ref" "svc:$svc_name" "ready" "checkmark.circle.fill" "#10B981"
      if [[ -n "$svc_url" ]]; then
        "$CMUX" new-surface --type browser --workspace "$ws_ref" \
          --pane "${pane_refs[browser]:-$initial_pane}" --url "$svc_url" 2>/dev/null || true
      fi
    else
      ws_set_status "$ws_ref" "svc:$svc_name" "timeout" "exclamationmark.triangle.fill" "#EF4444"
      ws_log "$ws_ref" "Service $svc_name did not start within ${svc_timeout}s"
    fi
  done

  # --- 7. Set status items ---
  local status_count
  status_count=$(echo "$config_json" | jq '.status // [] | length')

  for ((i = 0; i < status_count; i++)); do
    local st_json st_key st_val st_icon st_color
    st_json=$(echo "$config_json" | jq ".status[$i]")
    st_key=$(echo "$st_json" | jq -r '.key')
    st_val=$(echo "$st_json" | jq -r '.value')
    st_icon=$(echo "$st_json" | jq -r '.icon // empty')
    st_color=$(echo "$st_json" | jq -r '.color // empty')
    ws_set_status "$ws_ref" "$st_key" "$st_val" "$st_icon" "$st_color"
  done

  # Factory integration
  local factory_agent
  factory_agent=$(echo "$config_json" | jq -r '.factory.agent // empty')
  if [[ -n "$factory_agent" ]]; then
    ws_set_status "$ws_ref" "agent" "$factory_agent" "person.fill" ""
  fi

  ws_set_status "$ws_ref" "state" "running" "play.circle.fill" "#10B981"
  ws_set_progress "$ws_ref" "1.0" "Ready"
  sleep 1
  ws_clear_progress "$ws_ref"

  # --- 8. Write lock file ---
  echo "$ws_ref" > "$project_dir/.workspace.lock"

  # Focus the first pane
  local first_pane_name
  first_pane_name=$(echo "$config_json" | jq -r '.layout.panes[0].name')
  "$CMUX" focus-pane --pane "${pane_refs[$first_pane_name]:-$initial_pane}" \
    --workspace "$ws_ref" 2>/dev/null || true

  ws_log "$ws_ref" "Workspace launched: $display_name"

  # --- 9. Post-launch hooks ---
  ws_run_hooks "post-launch" "$name" "$ws_ref"

  echo "  Workspace ready: $display_name"
}
