#!/usr/bin/env bash
# ws-journal.sh — JSONL workspace journal for continuity across sessions
#
# Each workspace gets a .journal.jsonl — an append-only log of events,
# findings, open questions, and stage transitions. Claude reads the tail
# on session start to resume where it left off.

WS_JOURNAL_DEFAULT_TAIL=30
WS_JOURNAL_MAX_LINES=500

ws_journal_path() {
  local name="$1"
  echo "$(ws_project_dir "$name")/.journal.jsonl"
}

ws_journal_append() {
  local name="$1" type="$2" text="$3"
  shift 3

  local journal
  journal=$(ws_journal_path "$name")
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Build JSON entry — extra fields passed as key=value pairs
  local json
  json=$(jq -cn \
    --arg ts "$ts" \
    --arg type "$type" \
    --arg text "$text" \
    '{ts: $ts, type: $type, text: $text}')

  # Merge any extra key=value args
  while [[ $# -gt 0 ]]; do
    local key="${1%%=*}" val="${1#*=}"
    json=$(echo "$json" | jq -c --arg k "$key" --arg v "$val" '. + {($k): $v}')
    shift
  done

  echo "$json" >> "$journal"

  # Rotate if over max
  ws_journal_rotate "$name"
}

ws_journal_read() {
  local name="$1" count="${2:-$WS_JOURNAL_DEFAULT_TAIL}"
  local journal
  journal=$(ws_journal_path "$name")

  if [[ ! -f "$journal" ]]; then
    echo "  No journal entries for $name"
    return 0
  fi

  tail -n "$count" "$journal"
}

ws_journal_query() {
  local name="$1" filter_type="$2" count="${3:-$WS_JOURNAL_DEFAULT_TAIL}"
  local journal
  journal=$(ws_journal_path "$name")

  [[ -f "$journal" ]] || return 0

  jq -c "select(.type == \"$filter_type\")" "$journal" | tail -n "$count"
}

ws_journal_summary() {
  local name="$1" count="${2:-$WS_JOURNAL_DEFAULT_TAIL}"
  local journal
  journal=$(ws_journal_path "$name")

  if [[ ! -f "$journal" ]]; then
    echo "  No journal for $name"
    return 0
  fi

  local total
  total=$(wc -l < "$journal" | tr -d ' ')

  echo ""
  echo "  Journal: $name ($total entries, showing last $count)"
  echo "  ──────────────────────────────────────────"

  tail -n "$count" "$journal" | while IFS= read -r line; do
    local ts type text
    ts=$(echo "$line" | jq -r '.ts // ""' 2>/dev/null)
    type=$(echo "$line" | jq -r '.type // ""' 2>/dev/null)
    text=$(echo "$line" | jq -r '.text // ""' 2>/dev/null)

    # Format timestamp to local short form
    local short_ts
    short_ts=$(echo "$ts" | cut -c6-16 | tr 'T' ' ')

    local icon
    case "$type" in
      session_start)  icon=">" ;;
      session_end)    icon="<" ;;
      finding)        icon="*" ;;
      open_question)  icon="?" ;;
      decision)       icon="!" ;;
      stage_change)   icon="#" ;;
      note)           icon="-" ;;
      *)              icon="." ;;
    esac

    printf "  %s %s  %-15s %s\n" "$icon" "$short_ts" "[$type]" "$text"
  done
  echo ""
}

ws_journal_rotate() {
  local name="$1"
  local journal
  journal=$(ws_journal_path "$name")

  [[ -f "$journal" ]] || return 0

  local lines
  lines=$(wc -l < "$journal" | tr -d ' ')

  if (( lines > WS_JOURNAL_MAX_LINES )); then
    local keep=$(( WS_JOURNAL_MAX_LINES * 3 / 4 ))
    local archive="${journal%.jsonl}.$(date +%Y%m%d).jsonl"
    cp "$journal" "$archive"
    tail -n "$keep" "$journal" > "${journal}.tmp"
    mv "${journal}.tmp" "$journal"
  fi
}

ws_journal_cmd() {
  local name="" type="" count="" text="" subcmd="show"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type=*)  type="${1#*=}"; shift ;;
      --type)    type="$2"; shift 2 ;;
      -n)        count="$2"; shift 2 ;;
      --add)     subcmd="add"; shift; text="$*"; break ;;
      --finding) subcmd="add"; type="finding"; shift; text="$*"; break ;;
      --question) subcmd="add"; type="open_question"; shift; text="$*"; break ;;
      --decision) subcmd="add"; type="decision"; shift; text="$*"; break ;;
      --note)    subcmd="add"; type="note"; shift; text="$*"; break ;;
      --raw)     subcmd="raw"; shift ;;
      --context) subcmd="context"; shift ;;
      -*)        ws_die "Unknown flag: $1. Usage: ws journal <name> [--type=TYPE] [-n COUNT] [--add TEXT]" ;;
      *)         [[ -z "$name" ]] && name="$1" || { text="$*"; break; }; shift ;;
    esac
  done

  [[ -z "$name" ]] && ws_die "Usage: ws journal <name> [--type=TYPE] [-n COUNT] [--add TEXT]"

  local project_dir
  project_dir=$(ws_project_dir "$name")
  [[ -d "$project_dir" ]] || ws_die "Project not found: $name"

  case "$subcmd" in
    add)
      [[ -z "$text" ]] && ws_die "Usage: ws journal <name> --add <text>"
      ws_journal_append "$name" "${type:-note}" "$text"
      echo "  Logged: [$type] $text"
      ;;
    raw)
      if [[ -n "$type" ]]; then
        ws_journal_query "$name" "$type" "${count:-30}"
      else
        ws_journal_read "$name" "${count:-30}"
      fi
      ;;
    context)
      ws_journal_context "$name" "${count:-20}"
      ;;
    show)
      if [[ -n "$type" ]]; then
        # Filter then pretty-print
        local tmpfile
        tmpfile=$(mktemp)
        ws_journal_query "$name" "$type" "${count:-30}" > "$tmpfile"
        local filtered_count
        filtered_count=$(wc -l < "$tmpfile" | tr -d ' ')
        echo ""
        echo "  Journal: $name (type=$type, $filtered_count entries)"
        echo "  ──────────────────────────────────────────"
        while IFS= read -r line; do
          local ts txt
          ts=$(echo "$line" | jq -r '.ts // ""' 2>/dev/null)
          txt=$(echo "$line" | jq -r '.text // ""' 2>/dev/null)
          local short_ts
          short_ts=$(echo "$ts" | cut -c6-16 | tr 'T' ' ')
          printf "  %s  %s\n" "$short_ts" "$txt"
        done < "$tmpfile"
        echo ""
        rm -f "$tmpfile"
      else
        ws_journal_summary "$name" "${count:-30}"
      fi
      ;;
  esac
}

ws_journal_context() {
  # Output the last N entries as a context block suitable for Claude to read
  local name="$1" count="${2:-20}"
  local journal
  journal=$(ws_journal_path "$name")

  [[ -f "$journal" ]] || return 0

  echo "## Recent Journal (last $count entries)"
  echo '```jsonl'
  tail -n "$count" "$journal"
  echo '```'
}
