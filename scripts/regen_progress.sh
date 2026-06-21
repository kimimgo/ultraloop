#!/usr/bin/env bash
# regen_progress.sh — 보드(SoT) → PROGRESS.md 재생성(읽기전용 뷰). 매 loop ①.
#   PROGRESS.md 는 절대 직접 편집하지 않는다 — 여기서만 보드로부터 다시 그린다.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
SKILL_DIR="$(cd "$SDIR/.." && pwd)"
REPO="$(ue_repo)"; PROJ="$(cfg_get roadmap.project_number "")"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
STATE_DIR="$(ue_state_dir)"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
{
  echo "<!-- ⚠️ 자동 재생성 파일 — 직접 편집 금지. 보드(SoT)에서 regen_progress.sh가 다시 그림 -->"
  echo "# PROGRESS (읽기전용 뷰) · $TS"
  echo
  echo "- repo: \`$REPO\`  · board: \`${PROJ:-(미설정)}\`"
  HB="$STATE_DIR/heartbeat"; [ -f "$HB" ] && echo "- last heartbeat: $(date -d @"$(cat "$HB")" '+%H:%M:%S' 2>/dev/null || cat "$HB")"
  LC="$STATE_DIR/loop-count"; [ -f "$LC" ] && echo "- loops: $(cat "$LC")"
  echo
  echo "## 보드 상태 요약"
  if [ -n "$PROJ" ] && command -v gh >/dev/null 2>&1; then
    GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh project item-list "$PROJ" --owner "${REPO%%/*}" --format json 2>/dev/null \
      | python3 -c 'import json,sys,collections
try:
 d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
 c=collections.Counter(str(it.get("status","?")) for it in items)
 for k,v in sorted(c.items()): print(f"- {k}: {v}")
 print(f"- 합계: {len(items)}")
except Exception as e: print(f"- (보드 조회 실패: {e})")' 2>/dev/null || echo "- (보드 조회 실패)"
  else
    echo "- (보드 미설정 — roadmap_sync 필요)"
  fi
  echo
  echo "## 승인 큐 대기"
  AQ="$STATE_DIR/../ultraloop-approvals"; [ -d "$AQ" ] && ls "$AQ"/*.pending 2>/dev/null | sed 's#.*/#- #' || echo "- (없음)"
  echo
  echo "## 블로커(blocked 이슈)"
  command -v gh >/dev/null 2>&1 && gh issue list -R "$REPO" --label blocked --state open --json number,title -q '.[]|"- #\(.number) \(.title)"' 2>/dev/null || true
} > PROGRESS.md 2>/dev/null || { ue_log "PROGRESS.md 쓰기 실패"; exit 1; }
ue_log "PROGRESS.md 재생성"
