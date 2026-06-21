#!/usr/bin/env bash
# board_bootstrap.sh — N레포 공유 보드 멱등 부트스트랩 (multi-repo-orchestration.md §2·§3)
#   1 보드 query-then-create → N레포 link → Stage 필드(옵션) 보장. 전부 gh api graphql
#   (graphql = gh 버전무관 멱등 경로. 신버전 gh면 `gh project`도 가능 — multi-repo §3). 토큰 project 스코프 필수.
# usage: board_bootstrap.sh [--dry-run]
#   exit 0=ok · 2=설정부족(repos<2 또는 board.shared!=true) · 5=API 실패
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

REPOS_JSON="$(cfg_get repos "[]")"
N=$(printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
[ "$N" -ge 2 ] || { ue_log "repos < 2 — N레포 모드 아님(단일 레포는 기존 부트스트랩)"; exit 2; }
[ "$(cfg_get board.shared false)" = "true" ] || { ue_log "board.shared != true — 공유 보드 모드 아님"; exit 2; }

TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
export GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}"
FIRST="$(printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["name"])')"
OWNER="${FIRST%%/*}"
TITLE="$(cfg_get board.title "")"
[ -n "$TITLE" ] || TITLE="$(basename "$FIRST") Platform"

gq() { gh api graphql "$@" 2>/tmp/ue_bb.err; }

# ── 1. 보드 query-then-create (멱등) ─────────────────────────────────────────
PNODE="$(cfg_get roadmap.project_node_id "")"
if [ -z "$PNODE" ]; then
  PNODE="$(gq -f query='query($login:String!){ user(login:$login){ projectsV2(first:50){ nodes{ id title number } } } }' \
    -f login="$OWNER" --jq ".data.user.projectsV2.nodes[] | select(.title==\"$TITLE\") | .id" | head -1)"
fi
if [ -z "$PNODE" ]; then
  if [ "$DRY" = 1 ]; then echo "DRY: createProjectV2 title=\"$TITLE\" owner=$OWNER"; else
    OID="$(gq -f query='query($login:String!){ user(login:$login){ id } }' -f login="$OWNER" --jq .data.user.id)"
    [ -n "$OID" ] || { ue_log "owner id 조회 실패: $(head -1 /tmp/ue_bb.err)"; exit 5; }
    PNODE="$(gq -f query='mutation($oid:ID!,$t:String!){ createProjectV2(input:{ownerId:$oid,title:$t}){ projectV2{ id number } } }' \
      -f oid="$OID" -f t="$TITLE" --jq .data.createProjectV2.projectV2.id)"
    [ -n "$PNODE" ] || { ue_log "보드 생성 실패: $(head -1 /tmp/ue_bb.err)"; exit 5; }
  fi
fi
PNUM="$([ -n "$PNODE" ] && gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { number } } }' -f id="$PNODE" --jq .data.node.number || true)"
echo "board: title=\"$TITLE\" node_id=${PNODE:-"(dry)"} number=${PNUM:-?}"
echo "  → ultraloop.config.yaml roadmap.project_node_id/number 에 기록하라(멱등 키)."

# ── 2. N레포 link (이미 link면 mutation이 멱등 no-op) ────────────────────────
printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
for r in json.load(sys.stdin): print(r["name"])' | while read -r R; do
  if [ "$DRY" = 1 ]; then echo "DRY: link $R"; continue; fi
  RID="$(gh api "repos/$R" --jq .node_id 2>/dev/null)"
  [ -n "$RID" ] || { echo "  ✗ $R node_id 조회 실패(레포 없음/권한)"; continue; }
  gq -f query='mutation($p:ID!,$r:ID!){ linkProjectV2ToRepository(input:{projectId:$p,repositoryId:$r}){ repository{ nameWithOwner } } }' \
    -f p="$PNODE" -f r="$RID" >/dev/null && echo "  ✓ link $R" || echo "  ✗ link $R 실패: $(head -1 /tmp/ue_bb.err)"
done

# ── 3. Stage 필드 (single-select, board.stage_options 있을 때만) ─────────────
OPTS_JSON="$(cfg_get board.stage_options "[]")"
NOPT=$(printf '%s' "$OPTS_JSON" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
if [ "$NOPT" -ge 1 ] && [ "$DRY" != 1 ] && [ -n "$PNODE" ]; then
  HAVE="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { fields(first:50){ nodes{ ... on ProjectV2FieldCommon { name } } } } } }' \
    -f id="$PNODE" --jq '.data.node.fields.nodes[].name' | grep -cx "Stage" || true)"
  if [ "${HAVE:-0}" -ge 1 ]; then echo "  ✓ Stage 필드 이미 존재(멱등)"; else
    OPTS_GQL="$(printf '%s' "$OPTS_JSON" | python3 -c 'import json,sys
print(",".join("{name:\"%s\",color:GRAY,description:\"\"}" % o for o in json.load(sys.stdin)))')"
    gq -f query="mutation(\$p:ID!){ createProjectV2Field(input:{projectId:\$p,dataType:SINGLE_SELECT,name:\"Stage\",singleSelectOptions:[$OPTS_GQL]}){ projectV2Field{ ... on ProjectV2FieldCommon { name } } } }" \
      -f p="$PNODE" >/dev/null && echo "  ✓ Stage 필드 생성($NOPT 옵션)" || echo "  ✗ Stage 필드 실패: $(head -1 /tmp/ue_bb.err)"
  fi
elif [ "$NOPT" -ge 1 ]; then echo "DRY: Stage 필드($NOPT 옵션)"; fi
echo "== board bootstrap done =="
