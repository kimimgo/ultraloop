#!/usr/bin/env bash
# goal-stop-gate.sh — /goal 정지 차단 게이트의 재현 (Stop 훅).
#
# 동작(내장 /goal 1:1): 에이전트가 멈추려 할 때마다 DoD 충족 여부를 재검사한다.
#   - 충족  → 정지 허용(goal clear).
#   - 미충족 → 정지 차단 + iteration/last_reason 누적 + 계속.
#
# ★ 안전(의무, 끌 수 없음): 가드 없는 Stop훅 재투입은 폭주한다(과거 사고). 그래서 *항상* FAIL-OPEN.
#   에러·상한·잠금 등 의심스러우면 무조건 **정지 허용**(루프에 사람을 가두지 않는다).
#   정지 *차단*은 (1)잠금 통과 (2)예산 통과 (3)iteration 미초과 (4)goal 미충족 4박자가 다 맞을 때만.
#
# 설치: 대상 레포 .claude/settings.json 의 hooks.Stop (assets/hooks/settings.snippet.json).
# 호출: 절대경로로 `bash <skill>/assets/hooks/goal-stop-gate.sh` (cwd=레포 루트, stdin=훅 페이로드).
# 출력: 차단 시 stdout에 {"decision":"block","reason":"..."} · 허용 시 exit 0(무출력).

set -uo pipefail
exec 9<&0 || true   # stdin(훅 페이로드) — 현재는 stop_hook_active만 참고

# --- 자기 위치 → 스킬 루트 → _lib.sh ---------------------------------------
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
# shellcheck source=/dev/null
. "$SKILL_DIR/scripts/_lib.sh" 2>/dev/null || { exit 0; }   # lib 없으면 정지 허용

allow() { exit 0; }                                  # 정지 허용(무출력)
block() { printf '{"decision":"block","reason":%s}\n' "$(_json "$1")"; exit 0; }
_json() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || printf '"%s"' "$(printf '%s' "$1" | tr -d '"\n')"; }

# --- goal 비활성이면 게이트 없음 -------------------------------------------
[ "$(cfg_get engine.goal.enabled true)" = "true" ] || allow

STATE_DIR="$(ue_state_dir)"
REPO_KEY="$(printf '%s' "$(pwd)" | cksum | cut -d' ' -f1)"
STATE="$STATE_DIR/goal-$REPO_KEY.state"
# config의 lock_file 이 비어 있으면(""=명시적 빈값) cfg_get 이 그 빈값을 돌려주므로
# default 가 안 먹는다 → 빈 경우 uid별 기본 경로로 폴백(잠금 가드가 무력화되지 않도록).
LOCK="$(cfg_get engine.goal.lock_file "")"
[ -n "$LOCK" ] || LOCK="$STATE_DIR/ultraloop-goal-$(id -u).lock"

# --- 가드 1: 잠금(재진입 차단). 잠겨 있고 신선하면 이중 게이트 방지 위해 정지 허용 ----
if [ -e "$LOCK" ]; then
  # 10분 stale 청소
  if [ -n "$(find "$LOCK" -mmin +10 2>/dev/null)" ]; then rm -f "$LOCK" 2>/dev/null || true
  else allow; fi
fi
( echo $$ > "$LOCK" ) 2>/dev/null || true
trap 'rm -f "$LOCK" 2>/dev/null || true' EXIT

# --- 가드 2: 예산(cost_guard). budget-stop(exit 7)이면 정지 허용 -----------
if [ -x "$SKILL_DIR/scripts/cost_guard.sh" ]; then
  bash "$SKILL_DIR/scripts/cost_guard.sh" >/dev/null 2>&1
  if [ "$?" -eq 7 ]; then
    bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop budget-stop" "예산 상한 도달 → 안전 정지(미완)" >/dev/null 2>&1 || true
    allow
  fi
fi

# --- 가드 3: iteration 상한 ------------------------------------------------
ITER=0; [ -f "$STATE" ] && ITER="$(grep -E '^ITER=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2)"; ITER="${ITER:-0}"
MAXIT="$(cfg_get engine.goal.max_iterations 200)"; MAXIT="${MAXIT:-200}"
if [ "$ITER" -ge "$MAXIT" ] 2>/dev/null; then
  bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop goal escalation" "iteration 상한($MAXIT) 도달 → 정지 허용(미완). 사람 확인 필요." >/dev/null 2>&1 || true
  allow
fi

# --- goal 충족 평가 (goal_check.sh) ----------------------------------------
REASON=""
if [ -x "$SKILL_DIR/scripts/goal_check.sh" ]; then
  REASON="$(bash "$SKILL_DIR/scripts/goal_check.sh" 2>/dev/null)"; RC=$?
else
  RC=0   # 평가기 없으면 충족으로 보고 정지 허용(FAIL-OPEN)
fi

if [ "$RC" -eq 0 ]; then
  { echo "ITER=$ITER"; echo "STATUS=met"; echo "LAST_REASON=goal met"; } > "$STATE" 2>/dev/null || true
  allow
fi

# --- 미충족 → iteration++ + (무진척 stall 가드) + reason 기록 + 정지 차단 -----
ITER=$((ITER+1))
[ -z "$REASON" ] && REASON="DoD 미충족 — 보드/CI/E2E/HITL 확인 필요"

# 가드 4: 무진척(stall). goal_check 의 reason 이 직전과 byte-동일하면 관측 가능한 진척이 0이다
#   (예: 남은 카드가 전부 사용자 보류/blocked 라 "미종료 N개"가 영원히 안 줄어듦). 같은 blocker 가
#   max_stall_iterations 회 연속이면 정지 허용 + 에스컬레이션 — busywork·폭주를 iteration 상한(200)
#   훨씬 전에 끊는다. (2026-06-15 사고 동기: DoD 천장에서 12카드가 전부 보류라 게이트가 무한 재촉 →
#   429·컨텍스트 유실. references/failure-modes.md FM1.) 파싱 실패 시 STALL=0 → 기존 동작(fail-safe).
PREV_REASON=""; [ -f "$STATE" ] && PREV_REASON="$(grep -E '^LAST_REASON=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2-)"
STALL=0; [ -f "$STATE" ] && STALL="$(grep -E '^STALL=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2)"; STALL="${STALL:-0}"; case "$STALL" in ''|*[!0-9]*) STALL=0;; esac
if [ "$REASON" = "$PREV_REASON" ]; then STALL=$((STALL+1)); else STALL=0; fi
MAXSTALL="$(cfg_get engine.goal.max_stall_iterations 10)"; MAXSTALL="${MAXSTALL:-10}"; case "$MAXSTALL" in ''|*[!0-9]*) MAXSTALL=10;; esac
{ echo "ITER=$ITER"; echo "STATUS=not_met"; echo "STALL=$STALL"; echo "LAST_REASON=$REASON"; } > "$STATE" 2>/dev/null || true
if [ "$MAXSTALL" -gt 0 ] && [ "$STALL" -ge "$MAXSTALL" ] 2>/dev/null; then
  bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop stalled" "동일 blocker ${STALL}회 반복(무진척) → 정지 허용. 사람 입력 필요: $REASON" >/dev/null 2>&1 || true
  allow
fi
block "[$ITER/$MAXIT · stall $STALL/$MAXSTALL] 아직 끝나지 않았다. $REASON — 남은 일을 계속 진행하라(/ultraloop 루프)."
