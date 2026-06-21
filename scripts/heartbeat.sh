#!/usr/bin/env bash
# heartbeat.sh — 주기적 liveness 신호. 매 loop ①에서 호출.
# 상태파일 타임스탬프 갱신 + (옵션) Discord 알림. dead-man's-switch가 이 파일을 본다.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
STATE_DIR="$(ue_state_dir)"
date +%s > "$STATE_DIR/heartbeat"

MSG="${1:-loop alive}"
# heartbeat 알림은 소음이라 기본은 상태파일만. 명시 호출 시에만 Discord.
if [ "${2:-}" = "--notify" ]; then
  bash "$SDIR/notify.sh" heartbeat "ultraloop heartbeat" "$MSG" >/dev/null 2>&1 || true
fi
exit 0
