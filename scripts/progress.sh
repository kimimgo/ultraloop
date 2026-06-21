#!/usr/bin/env bash
# progress.sh — 진행률·E2E·DoD·추적성 요약(사람/에이전트용 한눈에). 읽기전용.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; PROJ="$(cfg_get roadmap.project_number "")"
STATE_DIR="$(ue_state_dir)"

echo "== ultraloop progress · $REPO =="
[ -f "$STATE_DIR/loop-count" ] && echo "loops: $(cat "$STATE_DIR/loop-count")"
[ -f "$STATE_DIR/run-start" ] && echo "elapsed: $(( ( $(date +%s) - $(cat "$STATE_DIR/run-start") ) / 60 )) min"

if command -v gh >/dev/null 2>&1; then
  echo "-- 이슈 --"
  echo "open:   $(gh issue list -R "$REPO" --state open --json number -q length 2>/dev/null || echo '?')"
  echo "blocked:$(gh issue list -R "$REPO" --label blocked --state open --json number -q length 2>/dev/null || echo '?')"
  echo "-- PR --"
  echo "open PR:$(gh pr list -R "$REPO" --state open --json number -q length 2>/dev/null || echo '?')"
fi
echo "-- E2E 증거 --"
[ -d ./e2e/reports ] && echo "reports: $(find ./e2e/reports -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" || echo "reports: 0"
echo "-- goal 게이트 상태 --"
ST="$STATE_DIR/goal-$(printf '%s' "$(pwd)" | cksum | cut -d' ' -f1).state"
[ -f "$ST" ] && cat "$ST" || echo "(아직 평가 없음)"
echo
echo "DoD 상세는 references/definition-of-done.md, goal 판정은 goal_check.sh"
