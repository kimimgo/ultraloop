#!/usr/bin/env bash
# cost_guard.sh — §15 비용/시간/loop 상한 점검. 매 loop ① + goal 게이트에서 호출.
#   exit 0 = 여유 있음(계속)
#   exit 7 = budget-stop(상한 초과 → 안전 정지)
# 점검: wall-clock · loop 수 · (가능하면) CI 분. 토큰은 세션 한도에 위임(여기선 best-effort).
# 비결정: 실제 토큰 회계는 하네스가 안다. 여기선 *확실히 셀 수 있는 것*만 결정적으로 막는다.

set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
STATE_DIR="$(ue_state_dir)"
START="$STATE_DIR/run-start"; LOOPS="$STATE_DIR/loop-count"

now=$(date +%s)
# 최초 호출 시 시작시각 기록
[ -f "$START" ] || echo "$now" > "$START"
start=$(cat "$START" 2>/dev/null || echo "$now")

# 인자: --no-tick = loop 카운트 증가 없이 검사만(goal Stop 게이트용). 기본 = tick(loop ① 1회).
TICK=1; [ "${1:-}" = "--no-tick" ] && TICK=0
# loop 카운트(tick 모드에서만 증가; 상한 검사용 cnt는 항상 읽는다)
cnt=0; [ -f "$LOOPS" ] && cnt=$(cat "$LOOPS" 2>/dev/null || echo 0)
[ "$TICK" = 1 ] && { cnt=$((cnt+1)); echo "$cnt" > "$LOOPS"; }

MAXH="$(cfg_get budgets.max_wall_clock_hours 24)";  MAXH="${MAXH:-24}"
MAXL="$(cfg_get budgets.max_loops 0)";              MAXL="${MAXL:-0}"

# wall-clock 상한
if [ "$MAXH" -gt 0 ] 2>/dev/null; then
  elapsed=$(( (now - start) / 3600 ))
  if [ "$elapsed" -ge "$MAXH" ]; then
    ue_log "budget-stop: wall-clock ${elapsed}h ≥ ${MAXH}h"; exit 7
  fi
fi
# loop 수 상한(0=무제한)
if [ "$MAXL" -gt 0 ] 2>/dev/null && [ "$cnt" -ge "$MAXL" ]; then
  ue_log "budget-stop: loops ${cnt} ≥ ${MAXL}"; exit 7
fi

# dead-man's-switch: 마지막 heartbeat 이후 무진전이면 경고(차단은 아님)
DMS="$(cfg_get budgets.dead_mans_switch_minutes 30)"; DMS="${DMS:-30}"
HB="$STATE_DIR/heartbeat"
if [ -f "$HB" ] && [ -n "$(find "$HB" -mmin +"$DMS" 2>/dev/null)" ]; then
  bash "$SDIR/notify.sh" warn "ultraloop dead-man" "${DMS}분 무진전 — 멈춤/행 의심" >/dev/null 2>&1 || true
fi

exit 0
