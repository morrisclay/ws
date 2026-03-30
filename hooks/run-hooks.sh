#!/usr/bin/env bash
# run-hooks.sh — Execute hooks for a given lifecycle event
#
# Usage: source this file, then call ws_run_hooks <event> <workspace-name> [extra-args...]
# Events: pre-scaffold, post-scaffold, pre-launch, post-launch, pre-stop, post-stop

WS_HOOKS_DIR="${WS_SYSTEM:-$HOME/AI/.workspace}/hooks"

ws_run_hooks() {
  local event="$1" name="$2"
  shift 2

  local hook_dir="$WS_HOOKS_DIR/$event.d"
  [[ -d "$hook_dir" ]] || return 0

  for hook in "$hook_dir"/*.sh; do
    [[ -x "$hook" ]] || continue
    WS_EVENT="$event" WS_NAME="$name" "$hook" "$@" || {
      echo "  warn: hook failed: $(basename "$hook")" >&2
    }
  done
}
