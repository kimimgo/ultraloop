#!/usr/bin/env bash
# heartbeat.sh — periodic liveness signal. Called at loop step ① each iteration.
# Refreshes the state-file timestamp + (optional) Discord notification. The dead-man switch watches this file.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
STATE_DIR="$(ue_state_dir)"
date +%s > "$STATE_DIR/heartbeat"

MSG="${1:-loop alive}"
# heartbeat notifications are noise, so the default is the state file only. Discord only when explicitly requested.
if [ "${2:-}" = "--notify" ]; then
  bash "$SDIR/notify.sh" heartbeat "ultraloop heartbeat" "$MSG" >/dev/null 2>&1 || true
fi
exit 0
