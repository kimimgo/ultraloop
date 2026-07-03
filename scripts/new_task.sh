#!/usr/bin/env bash
# new_task.sh <type> "<title>" ["<body>"] — create an issue + check out a branch (+ the agent moves the board card to In-Progress).
#   type ∈ feat|fix|test|refactor|chore|docs
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
TYPE="${1:?type}"; TITLE="${2:?title}"; BODY="${3:-}"

NUM="$(gh issue create -R "$REPO" --title "$TITLE" --label "type:$TYPE" --body "${BODY:-_(ultraloop)_}" 2>/dev/null \
       | grep -oE '[0-9]+$' | tail -1)"
[ -n "$NUM" ] || { ue_log "issue creation failed — gh returned no issue number; check gh auth status and repository access"; exit 1; }
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-40)"
BRANCH="$TYPE/$NUM-$SLUG"
git checkout "$DEFB" 2>/dev/null && git pull --ff-only origin "$DEFB" 2>/dev/null || true
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null || true
echo "✓ issue #$NUM · branch $BRANCH"
echo "$NUM"
