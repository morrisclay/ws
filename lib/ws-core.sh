#!/usr/bin/env bash
# ws-core.sh — Constants, cmux helpers, logging

WS_ROOT="$HOME/AI"
WS_SYSTEM="$WS_ROOT/.workspace"
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"

ws_die() {
  echo "  error: $1" >&2
  exit 1
}

ws_config_value() {
  local section="$1" key="$2" default="${3:-}"
  local config_file="$WS_SYSTEM/config.toml"
  if [[ ! -f "$config_file" ]]; then
    echo "$default"
    return
  fi
  # Minimal TOML reader: find [section] then key = "value"
  local in_section=false
  while IFS= read -r line; do
    # Strip comments and whitespace
    line="${line%%#*}"
    [[ -z "${line// }" ]] && continue
    if [[ "$line" =~ ^\[([a-zA-Z_-]+)\] ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
        in_section=true
      else
        $in_section && break
      fi
      continue
    fi
    if $in_section && [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"]*)\"? ]]; then
      echo "${BASH_REMATCH[1]}"
      return
    fi
  done < "$config_file"
  echo "$default"
}

ws_require_cmux() {
  if ! "$CMUX" ping >/dev/null 2>&1; then
    ws_die "cmux is not running. Open cmux.app first."
  fi
}

ws_require_deps() {
  command -v ruby >/dev/null 2>&1 || ws_die "ruby is required (should be pre-installed on macOS)"
  command -v jq >/dev/null 2>&1 || ws_die "jq is required. Install: brew install jq"
}

ws_project_dir() {
  echo "$WS_ROOT/$1"
}

ws_config_path() {
  echo "$WS_ROOT/$1/.workspace.yaml"
}

ws_is_running() {
  local name="$1"
  "$CMUX" --json list-workspaces 2>/dev/null \
    | jq -r ".workspaces[] | select(.title == \"$name\") | .ref" 2>/dev/null | head -1
}

ws_log() {
  local ws_ref="$1" msg="$2"
  "$CMUX" log --source ws --workspace "$ws_ref" -- "$msg" 2>/dev/null || true
}

ws_set_status() {
  local ws_ref="$1" key="$2" value="$3" icon="${4:-}" color="${5:-}"
  local args=("$key" "$value" --workspace "$ws_ref")
  [[ -n "$icon" ]] && args+=(--icon "$icon")
  [[ -n "$color" ]] && args+=(--color "$color")
  "$CMUX" set-status "${args[@]}" 2>/dev/null || true
}

ws_set_progress() {
  local ws_ref="$1" value="$2" label="${3:-}"
  local args=("$value" --workspace "$ws_ref")
  [[ -n "$label" ]] && args+=(--label "$label")
  "$CMUX" set-progress "${args[@]}" 2>/dev/null || true
}

ws_clear_progress() {
  local ws_ref="$1"
  "$CMUX" clear-progress --workspace "$ws_ref" 2>/dev/null || true
}

ws_available_templates() {
  ls -1 "$WS_SYSTEM/templates/" 2>/dev/null | tr '\n' ', ' | sed 's/,$//'
}

ws_resolve_project_dir() {
  local name="$1"

  # Try ~/AI/ first
  local project_dir="$WS_ROOT/$name"
  if [[ -d "$project_dir" ]]; then
    echo "$project_dir"
    return 0
  fi

  # Check registry for external workspaces
  local registry="$WS_SYSTEM/registry.jsonl"
  if [[ -f "$registry" ]]; then
    local ext_path
    ext_path=$(while IFS= read -r line; do
      local p n
      p=$(echo "$line" | jq -r '.path' 2>/dev/null)
      n=$(echo "$line" | jq -r '.name' 2>/dev/null)
      if [[ "$n" == "$name" && -d "$p" ]]; then
        echo "$p"
        break
      fi
    done < "$registry")
    if [[ -n "$ext_path" ]]; then
      echo "$ext_path"
      return 0
    fi
  fi

  return 1
}
