#!/usr/bin/env bash
# worktree_mgr.sh — parallel-lane worktree management. create | list | gc
#   gc protects in-flight lanes (REQ-WT-4): only finished (Done/merged) lanes are cleaned; when in doubt, preserve.
#     deterministic checks = ① uncommitted changes (exit 10) ② unmerged ahead commits (exit 11)  [git level, no tokens needed]
#     ④ preserve when a pending approval-queue item references this issue# (best-effort).
#     ③ board card state is pre-filtered by the orchestrator, which passes only Done lanes before calling gc (worktree-strategy.md).
#   gc exit 0=ok (removed something, or nothing to remove in the first place) · 2=kept because a preservation rule applied
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ROOT="$(cfg_get worktree.root ../.ue-worktrees)"
DEFB="$(cfg_get default_branch main)"
CMD="${1:-list}"

case "$CMD" in
  create)
    ISSUE="${2:?issue#}"; SLUG="${3:?slug}"
    WT="$ROOT/${ISSUE}-${SLUG}"; BR="feat/${ISSUE}-${SLUG}"   # the caller may override type via the branch name
    mkdir -p "$ROOT"
    git worktree add -b "$BR" "$WT" "origin/$DEFB" 2>/dev/null \
      || git worktree add "$WT" "$BR" 2>/dev/null \
      || { ue_log "worktree create failed: $WT — branch or path may already exist; inspect with git worktree list"; exit 1; }
    echo "$WT"
    ;;
  list)
    git worktree list 2>/dev/null
    ;;
  gc)
    removed=0; preserved=0
    QDIR="${TMPDIR:-/tmp}/ultraloop-approvals"
    # iterate over the git worktree list
    while read -r path _; do
      [ -z "$path" ] && continue
      case "$path" in *"$(basename "$ROOT")"*) : ;; *) continue ;; esac   # our lanes only
      # preservation rule ④ (best-effort): keep the lane when its issue# is referenced by a pending approval.
      ISSUE="$(basename "$path" | grep -oE '^[0-9]+' || true)"
      if [ -n "$ISSUE" ] && ls "$QDIR"/*.pending >/dev/null 2>&1 \
         && grep -qE "(^|[^0-9])#?${ISSUE}([^0-9]|$)" "$QDIR"/*.pending 2>/dev/null; then
        ue_log "gc: lane #$ISSUE referenced by a pending approval → preserved"; preserved=$((preserved+1)); continue
      fi
      ( cd "$path" 2>/dev/null || exit 0
        # preservation rule ①: uncommitted changes — git diff cannot see untracked files, so use status --porcelain (includes untracked).
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then exit 10; fi
        BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        # preservation rule ②: unmerged branch ahead of main
        git fetch -q origin "$DEFB" 2>/dev/null || true
        AHEAD="$(git rev-list --count "origin/$DEFB..$BR" 2>/dev/null || echo 1)"
        [ "${AHEAD:-1}" -gt 0 ] && exit 11
        exit 0 )
      rc=$?
      if [ "$rc" -eq 0 ]; then
        git worktree remove "$path" --force 2>/dev/null && removed=$((removed+1)) || preserved=$((preserved+1))
      else
        preserved=$((preserved+1))   # preserved (in-flight)
      fi
    done < <(git worktree list 2>/dev/null | awk '{print $1}')
    git worktree prune 2>/dev/null || true
    ue_log "gc: removed=$removed preserved=$preserved"
    # exit: 0=ok (removed or nothing to remove) · 2=kept by a preservation rule (distinct from nothing-to-do)
    if   [ "$removed"   -gt 0 ]; then exit 0
    elif [ "$preserved" -gt 0 ]; then exit 2
    else exit 0; fi
    ;;
  *) echo "usage: worktree_mgr.sh create <issue#> <slug> | list | gc"; exit 1 ;;
esac
