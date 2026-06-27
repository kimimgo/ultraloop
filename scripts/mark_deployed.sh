#!/usr/bin/env bash
# mark_deployed.sh [version] — 프로덕션 배포 완료 마커 기록(DoD 종료조건; goal_check 가 요구).
#   goal_check 는 ./.ultraloop/prod-deployed 를 '프로덕션 배포 성공' 증거로 본다. 이 스크립트가
#   그 유일한 생성 경로다(이전엔 생성처가 없어 정상 배포해도 goal 이 영영 안 닫혔다).
#   ★ 반드시 production HITL 승인 + 헬스 OK 를 확인한 뒤에만 호출(에이전트 또는 CD 후속 단계). 멱등.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"
VER="${1:-$(git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo '?')}"

# best-effort 검증: 최근 cd 워크플로 run 이 success 인지 확인(실패해도 차단하지 않음 — 헬스는 호출자가 확인).
if command -v gh >/dev/null 2>&1; then
  ST="$(gh run list -R "$REPO" --workflow cd --status success --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || echo '')"
  [ "$ST" = "success" ] && echo "  ✓ 최근 cd run=success 확인" || echo "  · cd run 성공 자동확인 못함(수동 검증 전제) — 계속"
fi

mkdir -p .ultraloop
printf 'version=%s\ndeployed_at=%s\n' "$VER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .ultraloop/prod-deployed
git add .ultraloop/prod-deployed 2>/dev/null || true
git commit -m "chore(ultraloop): mark production deployment ${VER}" >/dev/null 2>&1 \
  && echo "  ✓ .ultraloop/prod-deployed (version=$VER) 기록·커밋" \
  || echo "  ✓ .ultraloop/prod-deployed (version=$VER) 기록(커밋 변경 없음)"
