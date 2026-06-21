#!/usr/bin/env bash
# approval_queue.sh — 비동기 승인 큐(고위험 비차단). 파일 기반.
#   enqueue <action> <risk> [ttl_min]  : 큐 적재 + 알림(레인 park는 호출자가 보드에서)
#   drain                               : 해결된 항목 확인 → 0=처리할 Y 있음 안내 / 비차단
#   wait <id> [ttl_min]                 : 특정 항목 결과 대기(게이트웨이 봇/콘솔)
#   exit 0=Y승인 · 1=N거부 · 4=hold(TTL 무응답 → 에스컬레이션/defer)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
QDIR="${TMPDIR:-/tmp}/ultraloop-approvals"; mkdir -p "$QDIR"
TTL_DEF="$(cfg_get discord.approval_ttl_minutes 120)"
CMD="${1:-drain}"

new_id() { printf 'apr-%s-%s' "$(date +%s)" "$$"; }

case "$CMD" in
  enqueue)
    ACTION="${2:?action}"; RISK="${3:-high}"; TTL="${4:-$TTL_DEF}"
    ID="$(new_id)"
    { echo "id=$ID"; echo "action=$ACTION"; echo "risk=$RISK"; echo "ttl_min=$TTL"; echo "ts=$(date +%s)"; } > "$QDIR/$ID.pending"
    bash "$SDIR/notify.sh" approval-pending "ultraloop 승인 필요(고위험)" "[$RISK] $ACTION — 응답 대기(TTL ${TTL}m). 해당 레인 Parked, 다른 레인 계속." >/dev/null 2>&1 || true
    # 게이트웨이 봇이 있으면 버튼 띄우기(per-approval). 없으면 콘솔/폴링.
    if [ "$(cfg_get discord.mode gateway_bot)" = "gateway_bot" ] && command -v python3 >/dev/null 2>&1; then
      ( bash -c "python3 '$SDIR/approve_bot.py' '$ID' '$ACTION' '$RISK' '$TTL'" >/dev/null 2>&1 & ) || true
    fi
    echo "$ID"
    ;;
  drain)
    # 결과 파일(.result)이 생긴 항목을 보고. 비차단.
    found=0
    for r in "$QDIR"/*.result; do
      [ -e "$r" ] || continue
      id="$(basename "$r" .result)"; dec="$(head -1 "$r" 2>/dev/null)"
      echo "$id: $dec"; rm -f "$QDIR/$id.pending" 2>/dev/null; found=1
    done
    [ "$found" -eq 0 ] && echo "(대기 중 처리할 결과 없음)"
    exit 0
    ;;
  wait)
    ID="${2:?id}"; TTL="${3:-$TTL_DEF}"; deadline=$(( $(date +%s) + TTL*60 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if [ -f "$QDIR/$ID.result" ]; then
        case "$(head -1 "$QDIR/$ID.result")" in
          Y*|y*) exit 0 ;; N*|n*) exit 1 ;;
        esac
      fi
      sleep 5
    done
    # TTL 초과 → 에스컬레이션 + defer
    bash "$SDIR/notify.sh" warn "ultraloop 승인 TTL 초과" "id=$ID 무응답(${TTL}m) → 에스컬레이션/defer. 항목 후순위로." >/dev/null 2>&1 || true
    exit 4
    ;;
  *) echo "usage: approval_queue.sh enqueue <action> <risk> [ttl] | drain | wait <id> [ttl]"; exit 1 ;;
esac
