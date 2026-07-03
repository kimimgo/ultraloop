#!/usr/bin/env bash
# roadmap_bootstrap.sh — bootstrap one shared board across multiple repos (idempotent, graphql = gh version agnostic).
#   board query-then-create (or golden template copyProjectV2 clone) → N-repo link → ensure custom fields.
#   Token needs project+repo scopes.
# usage: roadmap_bootstrap.sh [--dry-run]
#   exit 0=ok · 2=insufficient config (repos empty or owner unresolved) · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

REPOS_JSON="$(cfg_get repos "[]")"
N=$(printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
[ "$N" -ge 1 ] || { ghr_log "config.repos is empty — at least 1 repo required; fill repos in gh-roadmap.config.yaml"; exit 2; }
FIRST="$(printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0])')"
OWNER="$(cfg_get board.owner "")"; [ -n "$OWNER" ] || OWNER="${FIRST%%/*}"
TITLE="$(cfg_get board.title "")"; [ -n "$TITLE" ] || TITLE="$OWNER Roadmap"
TEMPLATE="$(cfg_get board.template_node_id "")"

echo "[gh-roadmap bootstrap] owner=$OWNER title=\"$TITLE\" repos=$N template=${TEMPLATE:-none}"

# ── 1. board query-then-create (idempotent) ────────────────────────────────
PNODE="$(cfg_get board.project_node_id "")"
[ -z "$PNODE" ] && PNODE="$(ghr_owner_projects "$OWNER" | awk -F'\t' -v t="$TITLE" '$3==t{print $1; exit}')"
if [ -z "$PNODE" ]; then
  OID="$(ghr_owner_id "$OWNER")"; [ -n "$OID" ] || { ghr_log "owner id resolution failed: $OWNER (probable cause: wrong login or missing token scope) — check board.owner and the token"; exit 5; }
  if [ "$DRY" = 1 ]; then
    echo "DRY: $([ -n "$TEMPLATE" ] && echo "copyProjectV2 from $TEMPLATE" || echo createProjectV2) title=\"$TITLE\""
  elif [ -n "$TEMPLATE" ]; then
    PNODE="$(gq -f query='mutation($pid:ID!,$oid:ID!,$t:String!){ copyProjectV2(input:{projectId:$pid,ownerId:$oid,title:$t,includeDraftIssues:true}){ projectV2{ id } } }' \
      -f pid="$TEMPLATE" -f oid="$OID" -f t="$TITLE" --jq .data.copyProjectV2.projectV2.id)"
    [ -n "$PNODE" ] || { ghr_log "copyProjectV2 failed: $(head -1 /tmp/ghr_gq.err) — check board.template_node_id and the token project scope"; exit 5; }
    echo "  ✓ golden template cloned (views·Insights·workflows included — only auto-add excluded, assets/add-to-project.yml)"
  else
    PNODE="$(gq -f query='mutation($oid:ID!,$t:String!){ createProjectV2(input:{ownerId:$oid,title:$t}){ projectV2{ id } } }' \
      -f oid="$OID" -f t="$TITLE" --jq .data.createProjectV2.projectV2.id)"
    [ -n "$PNODE" ] || { ghr_log "createProjectV2 failed: $(head -1 /tmp/ghr_gq.err) — check the token project scope and the owner"; exit 5; }
    echo "  ✓ fresh board created (⚠️ no views/Insights — for a roadmap view, board.template_node_id is recommended)"
  fi
else
  echo "  ✓ using existing board (idempotent): $PNODE"
fi
[ "$DRY" = 1 ] && { echo "(dry-run end)"; exit 0; }
[ -n "$PNODE" ] || exit 5
PNUM="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { number } } }' -f id="$PNODE" --jq .data.node.number)"
echo "  board node_id=$PNODE number=${PNUM:-?}"
# auto-record into config (hardened 2026-06-21: previously only guidance was printed → if manual entry was missed, roadmap_item.sh exited 3 with board.project_node_id not set).
# sed replaces only that line to preserve comments/format (python yaml dump drops comments). If the line is missing, warn only.
_CFGF="$(ghr_config_path)"
if [ -f "$_CFGF" ] && grep -qE '^[[:space:]]*project_node_id:' "$_CFGF"; then
  sed -i -E "s|^([[:space:]]*project_node_id:).*|\1 \"$PNODE\"|" "$_CFGF"
  grep -qE '^[[:space:]]*project_number:' "$_CFGF" && sed -i -E "s|^([[:space:]]*project_number:).*|\1 \"${PNUM:-}\"|" "$_CFGF"
  echo "  ✓ config auto-recorded: $_CFGF (project_node_id/number)"
else
  echo "  ⚠️ config line project_node_id not found — manually set board.project_node_id=$PNODE in gh-roadmap.config.yaml (roadmap_item.sh runs on this value; ⚠️ the config is searched from cwd upward, so keep it at the working repo root)."
fi

# ── 2. N-repo link (idempotent no-op) ───────────────────────────────────────
printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
for r in json.load(sys.stdin): print(r)' | while read -r R; do
  RID="$(ghr_repo_node "$R")"; [ -n "$RID" ] || { echo "  ✗ $R node_id lookup failed (probable cause: repo missing or no access) — check the repos entry and token scopes"; continue; }
  gq -f query='mutation($p:ID!,$r:ID!){ linkProjectV2ToRepository(input:{projectId:$p,repositoryId:$r}){ repository{ nameWithOwner } } }' \
    -f p="$PNODE" -f r="$RID" >/dev/null 2>&1 && echo "  ✓ link $R" || echo "  ✗ link $R failed: $(head -1 /tmp/ghr_gq.err) — check the token project scope"
done

# ── 3. ensure custom fields (assets/fields.json, idempotent — skip if present) ──
HORIZONS="$(cfg_get horizons '["Long-term","Mid-term","Short-term"]')"
python3 - "$SDIR/../assets/fields.json" "$HORIZONS" <<'PY' | while IFS=$'\t' read -r FNAME FGQL; do
import json,sys
fields=json.load(open(sys.argv[1]))["fields"]; horizons=json.loads(sys.argv[2])
colors=["BLUE","GREEN","YELLOW","ORANGE","RED","PURPLE","PINK","GRAY"]
for f in fields:
    if f["name"]=="Horizon":
        f["options"]=[{"name":h,"color":colors[i%len(colors)]} for i,h in enumerate(horizons)]
    if f["dataType"]=="SINGLE_SELECT":
        opts=",".join('{name:"%s",color:%s,description:""}'%(o["name"],o.get("color","GRAY")) for o in f["options"])
        print(f["name"], 'dataType:SINGLE_SELECT,name:"%s",singleSelectOptions:[%s]'%(f["name"],opts), sep="\t")
    elif f["dataType"]=="DATE":
        print(f["name"], 'dataType:DATE,name:"%s"'%f["name"], sep="\t")
PY
  HAVE="$(ghr_field_meta "$PNODE" "$FNAME")"
  if [ -n "$HAVE" ]; then echo "  ✓ field already exists (idempotent): $FNAME"; continue; fi
  gq -f query="mutation(\$p:ID!){ createProjectV2Field(input:{projectId:\$p,$FGQL}){ projectV2Field{ ... on ProjectV2FieldCommon { name } } } }" \
     -f p="$PNODE" >/dev/null 2>&1 && echo "  ✓ field created: $FNAME" || echo "  ✗ field creation failed: $FNAME ($(head -1 /tmp/ghr_gq.err)) — check the token project scope and assets/fields.json"
done

# ── 4. Status option alignment (fresh board Todo/In Progress/Done → config.status_options) ──
#   ⚠️ Fixes the trap ultraloop hit — the default board has no Ready, so consumers read 0 items.
#   Align via updateProjectV2Field (idempotent: skip if already matching). A golden template usually matches already.
STATUS_OPTS="$(cfg_get status_options '[]')"
if [ "$STATUS_OPTS" != "[]" ] && [ -n "$STATUS_OPTS" ]; then
  META="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { fields(first:50){ nodes{ ... on ProjectV2SingleSelectField { id name options{ name } } } } } } }' -f id="$PNODE" \
    | python3 -c 'import json,sys
for f in json.load(sys.stdin)["data"]["node"]["fields"]["nodes"]:
    if f and f.get("name")=="Status": print(f["id"], "|".join(o["name"] for o in f["options"]), sep="\t"); break')"
  SID="$(printf '%s' "$META" | cut -f1)"; CUR="$(printf '%s' "$META" | cut -f2)"
  WANT="$(printf '%s' "$STATUS_OPTS" | python3 -c 'import json,sys;print("|".join(json.load(sys.stdin)))')"
  if [ -z "$SID" ]; then echo "  · Status field missing — skipping alignment"
  elif [ "$CUR" = "$WANT" ]; then echo "  ✓ Status options already match (idempotent): $WANT"
  else
    OPTS_GQL="$(printf '%s' "$STATUS_OPTS" | python3 -c 'import json,sys
cs=["GRAY","BLUE","YELLOW","ORANGE","GREEN","RED","PURPLE","PINK"]
print(",".join("{name:\"%s\",color:%s,description:\"\"}"%(o,cs[i%len(cs)]) for i,o in enumerate(json.load(sys.stdin))))')"
    gq -f query="mutation(\$f:ID!){ updateProjectV2Field(input:{fieldId:\$f,singleSelectOptions:[$OPTS_GQL]}){ projectV2Field{ ... on ProjectV2SingleSelectField { id } } } }" -f f="$SID" >/dev/null 2>&1 \
      && echo "  ✓ Status options aligned: ${CUR:-(default)} → $WANT" || echo "  ✗ Status option alignment failed: $(head -1 /tmp/ghr_gq.err) — check the token project scope"
  fi
fi

[ "$(cfg_get iteration false)" = "true" ] && echo "  · Add the Iteration field via the golden template/UI (ITERATION needs special duration·start setup — plain API creation not recommended)."
echo "== bootstrap complete =="
echo "next: roadmap_view.sh check (verify views/workflows) · roadmap_item.sh (create items)"
