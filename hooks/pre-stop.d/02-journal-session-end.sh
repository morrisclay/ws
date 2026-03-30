#!/usr/bin/env bash
# Log session_end to workspace journal
set -euo pipefail

WS_ROOT="$HOME/AI"
WS_SYSTEM="$WS_ROOT/.workspace"
source "$WS_SYSTEM/lib/ws-core.sh"
source "$WS_SYSTEM/lib/ws-journal.sh"

ws_journal_append "$WS_NAME" "session_end" "Workspace stopping"
