#!/usr/bin/env bash
# board.sh — GitHub Projects v2 보드 쓰기/조회 통합 CLI (graphql — gh 버전무관, 멱등)
#   지금까지 보드 '읽기'(meta_sync/roadmap_sync)만 스크립트였고 '쓰기'(카드 이동·필드·증거)는
#   에이전트가 매번 raw graphql을 손으로 짰다 — 루프 ⑧(보드 갱신)의 결정적 코어가 이 파일이다.
# usage:
#   board.sh add <issue-url> [--status <옵션명>] [--stage <옵션명>]   # 멱등 add(+필드 one-shot)
#   board.sh set <issue-url> <필드명> <값>     # SINGLE_SELECT(옵션명→id 자동) 또는 TEXT 필드 자동 판별
#   board.sh status <issue-url> <옵션명>       # set <url> Status <옵션명> 단축
#   board.sh evidence <issue-url> <텍스트>     # set <url> E2E-Evidence <텍스트> 단축
#   board.sh item <issue-url>                  # 보드 item-id 출력(없으면 빈 출력, exit 1)
# exit 0=ok · 1=item 없음(item만) · 3=보드 미설정 · 5=API 실패
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
PNODE="$(cfg_get roadmap.project_node_id "")"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
export GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}"
[ -n "$PNODE" ] || { ue_log "roadmap.project_node_id 미설정"; exit 3; }
gq() { gh api graphql "$@" 2>/tmp/ue_bd.err || { ue_log "graphql 실패: $(head -1 /tmp/ue_bd.err)"; exit 5; }; }

issue_node() { # issue URL → content node id
  gq -f query='query($u:URI!){ resource(url:$u){ ... on Issue { id } } }' -f u="$1" --jq .data.resource.id
}
add_item() { # 멱등: 이미 보드에 있으면 같은 item id 반환(GitHub 보장)
  local cid; cid="$(issue_node "$1")"; [ -n "$cid" ] || { ue_log "이슈 해석 실패: $1"; exit 5; }
  gq -f query='mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p,contentId:$c}){ item{ id } } }' \
     -f p="$PNODE" -f c="$cid" --jq .data.addProjectV2ItemById.item.id
}
field_meta() { # 필드명 → "fieldId<TAB>type<TAB>옵션JSON" (월드 1회 조회)
  gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { fields(first:50){ nodes {
      ... on ProjectV2FieldCommon { id name dataType }
      ... on ProjectV2SingleSelectField { options { id name } } } } } } }' -f id="$PNODE" \
  | python3 -c '
import json,sys
want=sys.argv[1]
for f in json.load(sys.stdin)["data"]["node"]["fields"]["nodes"]:
    if f and f.get("name")==want:
        print(f["id"], f.get("dataType",""), json.dumps(f.get("options",[]), ensure_ascii=False), sep="\t"); break' "$1"
}
set_field() { # <issue-url> <필드명> <값>
  local url="$1" fname="$2" val="$3" iid meta fid ftype opts
  iid="$(add_item "$url")"
  meta="$(field_meta "$fname")"; [ -n "$meta" ] || { ue_log "필드 없음: $fname"; exit 5; }
  fid="$(printf '%s' "$meta" | cut -f1)"; ftype="$(printf '%s' "$meta" | cut -f2)"
  if [ "$ftype" = "SINGLE_SELECT" ]; then
    opts="$(printf '%s' "$meta" | cut -f3)"
    OID="$(printf '%s' "$opts" | python3 -c '
import json,sys
v=sys.argv[1]
for o in json.load(sys.stdin):
    if o["name"]==v: print(o["id"]); break' "$val")"
    [ -n "$OID" ] || { ue_log "옵션 없음: $fname=$val (가용: $(printf '%s' "$opts" | python3 -c 'import json,sys;print(", ".join(o["name"] for o in json.load(sys.stdin)))'))"; exit 5; }
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){ projectV2Item{ id } } }' \
       -f p="$PNODE" -f i="$iid" -f f="$fid" -f o="$OID" >/dev/null
  else # TEXT 등
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$t:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{text:$t}}){ projectV2Item{ id } } }' \
       -f p="$PNODE" -f i="$iid" -f f="$fid" -f t="$val" >/dev/null
  fi
  echo "SET $fname=$val ($url)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
item)
  URL="${1:?usage: item <issue-url>}"
  IID="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { items(first:100){ totalCount nodes{ id content{ ... on Issue { url } } } } } } }' \
       -f id="$PNODE" | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]["node"]["items"]
if d["totalCount"]>100: print("WARN: 보드 100+ 카드 — 페이지네이션 미지원, 누락 가능", file=sys.stderr)
for it in d["nodes"]:
    if (it.get("content") or {}).get("url")==sys.argv[1]: print(it["id"]); break' "$URL")"
  [ -n "$IID" ] && echo "$IID" || exit 1 ;;
add)
  URL="${1:?usage: add <issue-url> [--status S] [--stage G]}"; shift
  IID="$(add_item "$URL")"; echo "ITEM $IID"
  while [ $# -gt 0 ]; do case "$1" in
    --status) set_field "$URL" "Status" "$2"; shift 2;;
    --stage)  set_field "$URL" "Stage"  "$2"; shift 2;;
    *) shift;; esac; done ;;
set)      set_field "${1:?url}" "${2:?field}" "${3:?value}" ;;
status)   set_field "${1:?url}" "Status" "${2:?옵션명}" ;;
evidence) set_field "${1:?url}" "E2E-Evidence" "${2:?텍스트}" ;;
*) echo "usage: board.sh add|set|status|evidence|item ..."; exit 5 ;;
esac
