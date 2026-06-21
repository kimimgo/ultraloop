#!/usr/bin/env bash
# new_task.sh <type> "<title>" ["<body>"] — 이슈 생성 + 브랜치 체크아웃(+ 보드 카드는 에이전트가 In-Progress로).
#   type ∈ feat|fix|test|refactor|chore|docs
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
TYPE="${1:?type}"; TITLE="${2:?title}"; BODY="${3:-}"

NUM="$(gh issue create -R "$REPO" --title "$TITLE" --label "type:$TYPE" --body "${BODY:-_(ultraloop)_}" 2>/dev/null \
       | grep -oE '[0-9]+$' | tail -1)"
[ -n "$NUM" ] || { ue_log "이슈 생성 실패"; exit 1; }
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-40)"
BRANCH="$TYPE/$NUM-$SLUG"
git checkout "$DEFB" 2>/dev/null && git pull --ff-only origin "$DEFB" 2>/dev/null || true
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null || true
echo "✓ issue #$NUM · branch $BRANCH"
echo "$NUM"
