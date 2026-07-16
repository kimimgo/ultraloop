#!/usr/bin/env bash
# board.sh — unified CLI for GitHub Projects v2 board writes/reads (graphql — gh-version independent, idempotent)
#   Until now only board *reads* (meta_sync/roadmap_sync) were scripted; for *writes* (card moves, fields, evidence)
#   the agent hand-wrote raw graphql every time — this file is the deterministic core of loop ⑧ (board update).
# usage:
#   board.sh add <issue-url> [--status <option-name>] [--stage <option-name>]   # idempotent add (+ fields one-shot)
#   board.sh set <issue-url> <field-name> <value>     # SINGLE_SELECT (option name→id auto), TEXT, or NUMBER field, auto-detected
#   board.sh status <issue-url> <option-name>       # shorthand for set <url> Status <option-name>
#   board.sh evidence <issue-url> <text>     # shorthand for set <url> E2E-Evidence <text>
#   board.sh design <issue-url> <doc-url>    # shorthand for set <url> Design-Doc <doc-url>
#   board.sh stage <issue-url> <option-name>   # shorthand for set <url> Stage <option-name>
#   board.sh wave <issue-url> <number>       # shorthand for set <url> Wave <number>
#   board.sh comment <issue-url> <text>      # post an issue comment (card=container progress mirror)
#   board.sh item <issue-url>                  # print board item-id (empty output + exit 1 if absent)
#   board.sh ensure-fields [project-node-id]   # create missing fields from assets/project-fields.json +
#                                              #   align Status options (idempotent; node-id arg overrides config)
# exit 0=ok · 1=item absent (item only) · 3=board not configured · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
PNODE="$(cfg_get roadmap.project_node_id "")"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
export GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}"
# ensure-fields may target an explicit node id (e.g. the golden template) without a config present.
if [ "${1:-}" = "ensure-fields" ] && [ -n "${2:-}" ]; then PNODE="$2"; fi
[ -n "$PNODE" ] || { ue_log "roadmap.project_node_id not set"; exit 3; }
gq() { gh api graphql "$@" 2>/tmp/ue_bd.err || { ue_log "graphql failed: $(head -1 /tmp/ue_bd.err)"; exit 5; }; }

issue_node() { # issue URL → content node id
  gq -f query='query($u:URI!){ resource(url:$u){ ... on Issue { id } } }' -f u="$1" --jq .data.resource.id
}
add_item() { # idempotent: if already on the board, the same item id is returned (GitHub guarantee)
  local cid; cid="$(issue_node "$1")"; [ -n "$cid" ] || { ue_log "issue resolution failed: $1"; exit 5; }
  gq -f query='mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p,contentId:$c}){ item{ id } } }' \
     -f p="$PNODE" -f c="$cid" --jq .data.addProjectV2ItemById.item.id
}
field_meta() { # field name → "fieldId<TAB>type<TAB>optionsJSON" (one lookup per field)
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
set_field() { # <issue-url> <field-name> <value>
  local url="$1" fname="$2" val="$3" iid meta fid ftype opts
  iid="$(add_item "$url")"
  meta="$(field_meta "$fname")"; [ -n "$meta" ] || { ue_log "field absent: $fname"; exit 5; }
  fid="$(printf '%s' "$meta" | cut -f1)"; ftype="$(printf '%s' "$meta" | cut -f2)"
  if [ "$ftype" = "SINGLE_SELECT" ]; then
    opts="$(printf '%s' "$meta" | cut -f3)"
    OID="$(printf '%s' "$opts" | python3 -c '
import json,sys
v=sys.argv[1]
for o in json.load(sys.stdin):
    if o["name"]==v: print(o["id"]); break' "$val")"
    [ -n "$OID" ] || { ue_log "option absent: $fname=$val (available: $(printf '%s' "$opts" | python3 -c 'import json,sys;print(", ".join(o["name"] for o in json.load(sys.stdin)))'))"; exit 5; }
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){ projectV2Item{ id } } }' \
       -f p="$PNODE" -f i="$iid" -f f="$fid" -f o="$OID" >/dev/null
  elif [ "$ftype" = "NUMBER" ]; then
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$n:Float!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{number:$n}}){ projectV2Item{ id } } }' \
       -f p="$PNODE" -f i="$iid" -f f="$fid" -F n="$val" >/dev/null
  else # TEXT etc.
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$t:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{text:$t}}){ projectV2Item{ id } } }' \
       -f p="$PNODE" -f i="$iid" -f f="$fid" -f t="$val" >/dev/null
  fi
  echo "SET $fname=$val ($url)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
item)
  URL="${1:?usage: item <issue-url>}"
  # --paginate + $endCursor/pageInfo: sweeps boards with 100+ cards in full to find the item-id (prevents omissions).
  IID="$(gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){ node(id:$id){ ... on ProjectV2 { items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor } nodes{ id content{ ... on Issue { url } } } } } } }' \
       -f id="$PNODE" 2>/tmp/ue_bd.err | python3 -c '
import json,sys
dec=json.JSONDecoder(); raw=sys.stdin.read().strip(); i=0; url=sys.argv[1]
while i<len(raw):
    o,i=dec.raw_decode(raw,i)
    items=((o.get("data",{}) or {}).get("node") or {}).get("items",{}) or {}
    for it in (items.get("nodes") or []):
        if (it.get("content") or {}).get("url")==url: print(it["id"]); sys.exit(0)
    while i<len(raw) and raw[i] in " \t\r\n": i+=1' "$URL")"
  [ -n "$IID" ] && echo "$IID" || exit 1 ;;
add)
  URL="${1:?usage: add <issue-url> [--status S] [--stage G]}"; shift
  IID="$(add_item "$URL")"; echo "ITEM $IID"
  while [ $# -gt 0 ]; do case "$1" in
    --status) set_field "$URL" "Status" "$2"; shift 2;;
    --stage)  set_field "$URL" "Stage"  "$2"; shift 2;;
    *) shift;; esac; done ;;
set)      set_field "${1:?url}" "${2:?field}" "${3:?value}" ;;
status)   set_field "${1:?url}" "Status" "${2:?option-name}" ;;
evidence) set_field "${1:?url}" "E2E-Evidence" "${2:?text}" ;;
design)   set_field "${1:?url}" "Design-Doc" "${2:?doc-url}" ;;
stage)    set_field "${1:?url}" "Stage" "${2:?option-name}" ;;
wave)     set_field "${1:?url}" "Wave" "${2:?number}" ;;
comment)  if gh issue comment "${1:?url}" --body "${2:?text}" >/dev/null; then echo "COMMENT ($1)"; else ue_log "comment failed: $1"; exit 5; fi ;;
ensure-fields)
  # v0.13.2: the ONLY reader of assets/project-fields.json — creates missing fields on the board and aligns
  # Status options (fresh boards ship Todo/In Progress/Done; without "Ready" the loop picks nothing).
  FJSON="$SDIR/../assets/project-fields.json"
  [ -f "$FJSON" ] || { ue_log "project-fields.json missing: $FJSON"; exit 5; }
  MF="$(mktemp)"; trap 'rm -f "$MF"' EXIT
  gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { fields(first:50){ nodes{
      ... on ProjectV2FieldCommon { id name dataType }
      ... on ProjectV2SingleSelectField { options { name } } } } } } }' -f id="$PNODE" > "$MF"
  PLAN="$(python3 - "$FJSON" "$MF" <<'PY'
import json,sys
want=json.load(open(sys.argv[1]))["fields"]
have={}
for f in json.load(open(sys.argv[2]))["data"]["node"]["fields"]["nodes"]:
    if f and f.get("name"):
        have[f["name"]]={"id":f.get("id"),"opts":[o["name"] for o in (f.get("options") or [])]}
cs=["GRAY","BLUE","YELLOW","ORANGE","GREEN","RED","PURPLE","PINK"]
def og(names): return ",".join('{name:"%s",color:%s,description:""}'%(n,cs[i%len(cs)]) for i,n in enumerate(names))
for f in want:
    n=f["name"]; dt=f["dataType"]; opts=f.get("options") or []
    if n=="Status":
        h=have.get("Status")
        if h and opts and h["opts"]!=opts: print("ALIGN\t%s\t%s\x01%s"%(n,h["id"],og(opts)))
        else: print("SKIP\t%s\t"%n)
        continue
    if n in have: print("SKIP\t%s\t"%n); continue
    if dt=="SINGLE_SELECT": print('CREATE\t%s\tdataType:SINGLE_SELECT,name:"%s",singleSelectOptions:[%s]'%(n,n,og(opts)))
    else: print('CREATE\t%s\tdataType:%s,name:"%s"'%(n,dt,n))
PY
)"
  FAILED=0
  while IFS=$'\t' read -r ACT NAME PAYLOAD; do
    [ -n "$ACT" ] || continue
    case "$ACT" in
      SKIP) echo "  = $NAME (exists)";;
      CREATE)
        if gh api graphql -f query="mutation(\$p:ID!){ createProjectV2Field(input:{projectId:\$p,$PAYLOAD}){ projectV2Field{ ... on ProjectV2FieldCommon { name } } } }" \
             -f p="$PNODE" >/dev/null 2>/tmp/ue_bd.err </dev/null; then echo "  ✓ created: $NAME"
        else echo "  ✗ create failed: $NAME ($(head -c120 /tmp/ue_bd.err))"; FAILED=1; fi ;;
      ALIGN)
        FID="${PAYLOAD%%$'\x01'*}"; OPTS="${PAYLOAD#*$'\x01'}"
        if gh api graphql -f query="mutation(\$f:ID!){ updateProjectV2Field(input:{fieldId:\$f,singleSelectOptions:[$OPTS]}){ projectV2Field{ ... on ProjectV2SingleSelectField { id } } } }" \
             -f f="$FID" >/dev/null 2>/tmp/ue_bd.err </dev/null; then echo "  ✓ Status options aligned"
        else echo "  ✗ Status align failed ($(head -c120 /tmp/ue_bd.err))"; FAILED=1; fi ;;
    esac
  done <<< "$PLAN"
  exit "$FAILED" ;;
*) echo "usage: board.sh add|set|status|evidence|design|stage|wave|comment|item ..."; exit 5 ;;
esac
