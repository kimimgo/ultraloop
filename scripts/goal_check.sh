#!/usr/bin/env bash
# goal_check.sh — DoD(=goal 조건) 충족 여부를 *기계검증 가능한 부분*으로 평가.
#   exit 0  = 충족(정지 허용)
#   exit 1  = 미충족 — stdout에 "남은 사유" 한 줄(게이트가 reason으로 씀)
#
# 비결정 원칙: 여기선 *기계로 확인 가능한 신호*만 본다(보드 카운트·CI·증거 파일·HITL 마커).
# 미묘한 품질 판단은 에이전트가 루프에서 한다. 신호가 불명확하면 **미충족(1)** 으로 보수적 판정.
#
# config.engine.goal.condition 이 "DoD"(기본)면 아래 검사. 자유 문자열이면 그 의도를 에이전트가 해석.

set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

REPO="$(ue_repo)"
COND="$(cfg_get engine.goal.condition DoD)"
fail() { echo "$1"; exit 1; }

# 자유 조건이면 자동 판정 불가 → 에이전트 판단으로 넘김(보수적 미충족, 단 reason 명시)
if [ "$COND" != "DoD" ]; then
  fail "조건='$COND' — 에이전트가 충족 여부를 직접 판정해야 함(기계검증 불가)"
fi
[ -n "$REPO" ] || fail "레포 미해석 — config.repo 또는 gh 인증 확인"

# 1) 보드: 미종료 카드가 남아 있으면 미충족.
#    (project-scope 토큰 필요. 조회 실패 시 보수적 미충족.)
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
PROJ="$(cfg_get roadmap.project_number "")"
if [ -n "$PROJ" ] && command -v gh >/dev/null 2>&1; then
  OWNER="${REPO%%/*}"
  # gh project는 ≥2.31 필요 — PATH 선두의 apt 구버전(2.4.0)이 가리면 ~/.local/bin/gh로 폴백
  # (roadmap_sync.sh와 동일한 버전무관성 — 없으면 기존처럼 보수적 미충족으로 떨어진다)
  GHP="gh"
  if ! gh project --help >/dev/null 2>&1 && [ -x "$HOME/.local/bin/gh" ]; then GHP="$HOME/.local/bin/gh"; fi
  # 공유 보드(board.shared=true)면 자기 레포 카드만 평가 — 워커 DoD = "자기 카드 Done"
  # (multi-repo §3·§5 — roadmap_sync는 필터하는데 goal_check만 전 보드를 세던 정합 버그)
  REPO_FILTER=""
  [ "$(cfg_get board.shared false)" = "true" ] && REPO_FILTER="$REPO"
  # 미종료(Done 아닌) 카드 수 — 실패하면 빈값
  OPEN="$( { GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" "$GHP" project item-list "$PROJ" --owner "$OWNER" --format json 2>/dev/null \
            | UE_REPO_FILTER="$REPO_FILTER" python3 -c 'import json,os,sys
try:
  d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
  repo=os.environ.get("UE_REPO_FILTER","").strip().lower()
  def mine(it):
    if not repo: return True
    cand=str(it.get("repository") or (it.get("content") or {}).get("repository") or "").lower().rstrip("/")
    return cand.endswith("/"+repo) or cand==repo
  n=sum(1 for it in items if mine(it) and str(it.get("status","")).lower() not in ("done","closed"))
  print(n)
except Exception: print("ERR")' ; } 2>/dev/null )"
  case "$OPEN" in
    0) : ;;                                   # 모든 카드 Done → 통과
    ERR|"") fail "보드 조회 실패(일시적일 수 있음) — 보수적 미충족" ;;
    *) fail "보드에 미종료 카드 ${OPEN}개 남음" ;;
  esac
elif [ "$(cfg_get roadmap.provider github_projects_v2)" = "milestones" ] && command -v gh >/dev/null 2>&1; then
  # 폴백(R2, roadmap-model §6): Projects v2 불가 → 이슈(=작업 카드) 기반.
  #   보드의 "non-Done 카드 수"에 대응 = 미종료(open) 이슈 수. 0이면 통과.
  OPEN="$(gh issue list -R "$REPO" --state open --limit 1000 --json number -q 'length' 2>/dev/null)"
  case "$OPEN" in
    0) : ;;                                   # 모든 이슈 close → 통과
    "") fail "이슈 조회 실패(일시적일 수 있음) — 보수적 미충족" ;;
    *) fail "미종료 이슈 ${OPEN}개 남음(보드 폴백: 모든 이슈 close 필요)" ;;
  esac
else
  fail "보드/마일스톤 미설정 — 로드맵 동기화 필요(roadmap.provider 확인)"
fi

# 2) 열린 blocked 이슈가 있으면 미충족.
if command -v gh >/dev/null 2>&1; then
  BLK="$(gh issue list -R "$REPO" --label blocked --state open --json number -q 'length' 2>/dev/null || echo 0)"
  [ "${BLK:-0}" -gt 0 ] 2>/dev/null && fail "열린 blocked 이슈 ${BLK}개"
fi

# 3) E2E 증거가 하나도 없으면 미충족(merge전 E2E 게이트 산출물).
if [ -d "./e2e/reports" ]; then
  CNT="$(find ./e2e/reports -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  [ "${CNT:-0}" -ge 1 ] || fail "E2E 증거 리포트 없음(e2e/reports/*.md)"
else
  fail "e2e/reports 디렉토리 없음 — Tier2 E2E 미수행"
fi

# 4) 프로덕션 HITL 승인 마커(에이전트가 배포 성공 시 기록).
HITL="$(cfg_get hitl.enabled true)"
if [ "$HITL" = "true" ]; then
  [ -f "./.ultraloop/prod-deployed" ] || fail "프로덕션 HITL 배포 미완(.ultraloop/prod-deployed 마커 없음)"
fi

# 모든 기계검증 통과 → 충족
exit 0
