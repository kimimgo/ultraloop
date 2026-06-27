#!/usr/bin/env bash
# worktree_mgr.sh — 병렬 레인 worktree 관리. create | list | gc
#   gc 는 in-flight 보호(REQ-WT-4): 종료(Done/머지)된 레인만 정리, 애매하면 보존.
#     결정적 검사 = ①미커밋(exit 10) ②미머지 ahead(exit 11)  [git 레벨, 토큰 불요]
#     ④승인 큐 pending 이 해당 issue# 참조 시 보존(best-effort).
#     ③보드 카드 상태는 오케스트레이터가 gc 호출 전 Done 레인만 넘겨 1차로 거른다(worktree-strategy.md).
#   gc exit 0=정상(지웠거나 지울 것이 처음부터 없음) · 2=보존규칙에 걸려 남김
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ROOT="$(cfg_get worktree.root ../.ue-worktrees)"
DEFB="$(cfg_get default_branch main)"
CMD="${1:-list}"

case "$CMD" in
  create)
    ISSUE="${2:?issue#}"; SLUG="${3:?slug}"
    WT="$ROOT/${ISSUE}-${SLUG}"; BR="feat/${ISSUE}-${SLUG}"   # type은 호출자가 브랜치명으로 덮어쓸 수 있음
    mkdir -p "$ROOT"
    git worktree add -b "$BR" "$WT" "origin/$DEFB" 2>/dev/null \
      || git worktree add "$WT" "$BR" 2>/dev/null \
      || { ue_log "worktree 생성 실패: $WT"; exit 1; }
    echo "$WT"
    ;;
  list)
    git worktree list 2>/dev/null
    ;;
  gc)
    removed=0; preserved=0
    QDIR="${TMPDIR:-/tmp}/ultraloop-approvals"
    # git worktree 목록을 순회
    while read -r path _; do
      [ -z "$path" ] && continue
      case "$path" in *"$(basename "$ROOT")"*) : ;; *) continue ;; esac   # 우리 레인만
      # 보존규칙④(best-effort): 이 레인 issue#가 승인 큐 pending에서 참조되면 보존.
      ISSUE="$(basename "$path" | grep -oE '^[0-9]+' || true)"
      if [ -n "$ISSUE" ] && ls "$QDIR"/*.pending >/dev/null 2>&1 \
         && grep -qE "(^|[^0-9])#?${ISSUE}([^0-9]|$)" "$QDIR"/*.pending 2>/dev/null; then
        ue_log "gc: 레인 #$ISSUE 승인 대기 참조 → 보존"; preserved=$((preserved+1)); continue
      fi
      ( cd "$path" 2>/dev/null || exit 0
        # 보존규칙①: 미커밋 변경 — git diff는 untracked 파일을 못 보므로 status --porcelain(untracked 포함).
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then exit 10; fi
        BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        # 보존규칙②: main보다 앞선 미머지 브랜치
        git fetch -q origin "$DEFB" 2>/dev/null || true
        AHEAD="$(git rev-list --count "origin/$DEFB..$BR" 2>/dev/null || echo 1)"
        [ "${AHEAD:-1}" -gt 0 ] && exit 11
        exit 0 )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        git worktree remove "$path" --force 2>/dev/null && removed=$((removed+1)) || preserved=$((preserved+1))
      else
        preserved=$((preserved+1))   # 보존(in-flight)
      fi
    done < <(git worktree list 2>/dev/null | awk '{print $1}')
    git worktree prune 2>/dev/null || true
    ue_log "gc: removed=$removed preserved=$preserved"
    # exit: 0=정상(지웠거나 지울 것 없음) · 2=보존규칙에 걸려 남김(nothing-to-do와 구분)
    if   [ "$removed"   -gt 0 ]; then exit 0
    elif [ "$preserved" -gt 0 ]; then exit 2
    else exit 0; fi
    ;;
  *) echo "usage: worktree_mgr.sh create <issue#> <slug> | list | gc"; exit 1 ;;
esac
