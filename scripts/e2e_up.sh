#!/usr/bin/env bash
# e2e_up.sh <issue#> — 레인 격리 실배포(merge 전 E2E의 'up'). 헬스 대기 → 시드.
#   레인별: compose project-name=ue-<issue#> · 동적 포트(base_port+issue) · 볼륨 격리.
# 비결정: runner=auto면 compose 우선, 없으면 README 단일명령. 실제 시드/헬스는 에이전트가 보강.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; PROJ="ue-${ISSUE}"
BASE="$(cfg_get e2e.base_port 14000)"; PORT=$((BASE + (ISSUE % 1000)))
RUNNER="$(cfg_get e2e.runner auto)"
TIMEOUT="$(cfg_get e2e.health_timeout_seconds 120)"
export UE_PORT="$PORT" UE_PROJECT="$PROJ"
echo "[e2e up] project=$PROJ port=$PORT runner=$RUNNER"

# 시크릿 주입(.env.e2e) — 평문 커밋 금지
SECRETS="$(cfg_get e2e.secrets_file .env.e2e)"
[ -f "$SECRETS" ] && echo "  · secrets: $SECRETS (주입)" || echo "  · secrets 없음($SECRETS) — 필요시 vault/GH Secrets에서 생성"

if { [ "$RUNNER" = "auto" ] || [ "$RUNNER" = "docker_compose" ]; } && command -v docker >/dev/null 2>&1 && ls docker-compose*.y*ml compose*.y*ml >/dev/null 2>&1; then
  UE_PORT="$PORT" docker compose -p "$PROJ" up -d 2>/dev/null || { ue_log "compose up 실패"; exit 1; }
  echo "  · compose up (project=$PROJ)"
else
  echo "  · README 단일 명령 기동으로 폴백 — 에이전트가 README의 기동 명령을 실행(rules/readme.md 계약)"
fi

# 헬스 대기(best-effort): 포트 열림 확인
echo "  · 헬스 대기(≤${TIMEOUT}s) on :$PORT"
for _ in $(seq 1 "$TIMEOUT"); do
  (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && { echo "  ✓ port $PORT up"; exit 0; }
  sleep 1
done
ue_log "헬스 타임아웃(:$PORT) — flake 가능. e2e_run이 재시도 판단"
exit 0   # up 자체는 통과로 두고, 판정은 run에서(flake 분류)
