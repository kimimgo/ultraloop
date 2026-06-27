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
    ue_log "디스크 ${USE}% — 안전 prune(dangling image + build cache) + 알림"
    # ★ 공유 self-hosted 호스트 — 전역 'docker system prune'(stopped 컨테이너·타 프로젝트 캐시 삭제) 금지.
    #   실행 중 자원·타 프로젝트 볼륨은 건드리지 않는 dangling 이미지/빌드 캐시만 회수한다.
    docker image prune -f 2>/dev/null || true
    docker builder prune -f 2>/dev/null || true
    bash "$SDIR/notify.sh" warn "ultraloop disk watchdog" "디스크 ${USE}% → dangling/빌드캐시 정리(전역 prune 안 함)" >/dev/null 2>&1 || true
  fi
fi
# 시크릿 폐기(.env.e2e 는 teardown 후 남기지 않음 — 단 사용자 제공 파일이면 보존)
exit 0
