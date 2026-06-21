#!/usr/bin/env bash
# ship_pr.sh ["title"] — push → PR → CI watch → ★merge 전 E2E → 통과 시 squash merge.
#   exit 0 = merge 완료 · 1 = CI 실패 · 6 = E2E 실패(merge 안 함)
# ★ E2E가 merge 전 게이트다. CI 녹색만으론 merge하지 않는다.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
TITLE="${1:-$(git log -1 --pretty=%s 2>/dev/null)}"

git push -u origin "$BR" 2>/dev/null || { ue_log "push 실패"; exit 1; }
gh pr view "$BR" >/dev/null 2>&1 || gh pr create -R "$REPO" --base "$DEFB" --head "$BR" --title "$TITLE" --fill 2>/dev/null || true

# CI 감시
echo "→ CI watch…"
if ! gh pr checks "$BR" --watch --interval 20 2>/dev/null; then
  ue_log "CI 실패 → 같은 브랜치에서 수정 재시도(보호 우회 금지)"; exit 1
fi

# ★ merge 전 E2E (게이트). 시나리오 인자는 환경/이슈에 맞게 에이전트가 결정.
ISSUE="$(printf '%s' "$BR" | grep -oE '[0-9]+' | head -1)"
echo "→ merge 전 E2E (issue ${ISSUE:-?})…"
if [ -x "$SDIR/e2e_up.sh" ]; then
  bash "$SDIR/e2e_up.sh" "${ISSUE:-0}" || { ue_log "E2E up 실패"; bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null; exit 6; }
  if ! bash "$SDIR/e2e_run.sh" "${ISSUE:-0}"; then
    ue_log "E2E 결정적 실패 → merge 안 함. e2e:fail + bug 이슈로."
    bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null || true
    exit 6
  fi
  bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null || true
else
  ue_log "e2e_up.sh 없음 — E2E 게이트 미수행(설정 확인)"; exit 6
fi

# 통과 → squash merge (증거 trailer는 에이전트가 e2e 리포트 경로로 추가)
gh pr merge "$BR" --squash --auto --delete-branch 2>/dev/null && { ue_log "merge 완료"; exit 0; }
ue_log "merge 실패(충돌/권한) — 직렬화 해소 후 재시도"; exit 1
