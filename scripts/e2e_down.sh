#!/usr/bin/env bash
# e2e_down.sh <issue#> — 레인 teardown + 누수 회수 + 디스크 watchdog.
#   격리 볼륨에 한해 down -v 허용(고위험 가드 예외 — observability/notify-approval).
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; PROJ="ue-${ISSUE}"

if command -v docker >/dev/null 2>&1; then
  docker compose -p "$PROJ" down -v 2>/dev/null && echo "[e2e down] $PROJ 정리(-v)" || true
  # 고아 컨테이너/볼륨 회수(이 프로젝트 라벨만)
  docker ps -aq --filter "label=com.docker.compose.project=$PROJ" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
  # 디스크 watchdog
  USE="$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')"
  if [ -n "$USE" ] && [ "$USE" -ge 85 ] 2>/dev/null; then
    ue_log "디스크 ${USE}% — prune + 알림"
    docker system prune -f 2>/dev/null || true
    bash "$SDIR/notify.sh" warn "ultraloop disk watchdog" "디스크 ${USE}% → docker prune 실행" >/dev/null 2>&1 || true
  fi
fi
# 시크릿 폐기(.env.e2e 는 teardown 후 남기지 않음 — 단 사용자 제공 파일이면 보존)
exit 0
