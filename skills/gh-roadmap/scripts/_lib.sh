#!/usr/bin/env bash
# _lib.sh — gh-roadmap shared helpers. Use via `source`. Intentionally thin (deterministic behavior only).
#   cfg_get <dotted.key> [default]            : read gh-roadmap.config.yaml (python yaml, fallback grep)
#   ghr_log <msg>                             : timestamped log (stderr)
#   gq <gh api graphql args...>               : graphql call (injects the token_env token). Failures are judged by the caller.
#   ghr_owner_id <login>                      : user/org owner node id (both supported)
#   ghr_owner_projects <login>                : projectsV2 of the owner (id<TAB>number<TAB>title) lines
#   ghr_issue_node <issue-url>                : issue content node id
#   ghr_repo_node <owner/repo>                : repo node id
#   ghr_add_item <pnode> <content-node>       : idempotent board add → item id (GitHub prevents duplicates)
#   ghr_field_meta <pnode> <name>             : "fieldId<TAB>dataType<TAB>optionsJSON" (empty output if missing)
#   ghr_set_field <pnode> <item> <name> <val> : set a field (SINGLE_SELECT option name→id automatic, otherwise TEXT/DATE)
# Token: if config board.token_env (or token_env) is set, that env var; otherwise the gh default (needs project+repo scopes).

ghr_skill_dir() {
  local s="${CLAUDE_SKILL_DIR:-}"
  [ -n "$s" ] || s="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s' "$s"
}

ghr_config_path() {
  if [ -n "${GHROADMAP_CONFIG:-}" ]; then printf '%s' "$GHROADMAP_CONFIG"; return; fi
  local d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/gh-roadmap.config.yaml" ] && { printf '%s' "$d/gh-roadmap.config.yaml"; return; }
    d="$(dirname "$d")"
  done
  printf '%s' "./gh-roadmap.config.yaml"
}

cfg_get() {
  local key="$1" def="${2:-}" cfg
  cfg="$(ghr_config_path)"
  [ -f "$cfg" ] || { printf '%s' "$def"; return 0; }
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" "$key" "$def" <<'PY' 2>/dev/null || printf '%s' "$def"
import sys
cfg, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    import yaml
    data = yaml.safe_load(open(cfg)) or {}
except Exception:
    print(default); sys.exit(0)
cur = data
for part in key.split('.'):
    if isinstance(cur, dict) and part in cur: cur = cur[part]
    else: print(default); sys.exit(0)
if cur is None: print(default)
elif isinstance(cur, bool): print('true' if cur else 'false')
elif isinstance(cur, (list, dict)):
    import json; print(json.dumps(cur, ensure_ascii=False))
else: print(cur)
PY
  else
    local last="${key##*.}"
    grep -E "^\s*${last}\s*:" "$cfg" 2>/dev/null | head -1 | sed -E 's/^[^:]*:\s*//; s/\s*$//; s/^["'\'']//; s/["'\'']$//' | grep . || printf '%s' "$def"
  fi
}

ghr_log() { printf '[gh-roadmap %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

ghr_token() {
  local te; te="$(cfg_get board.token_env "")"; [ -z "$te" ] && te="$(cfg_get token_env "")"
  if [ -n "$te" ] && [ -n "${!te:-}" ]; then printf '%s' "${!te}"; return; fi
  printf '%s' "${GH_TOKEN:-}"
}

gq() { GH_TOKEN="$(ghr_token)" gh api graphql "$@" 2>/tmp/ghr_gq.err; }

ghr_owner_id() {
  gq -f query='query($l:String!){ repositoryOwner(login:$l){ id } }' -f l="$1" --jq .data.repositoryOwner.id
}

ghr_owner_projects() { # id<TAB>number<TAB>title (both user/org)
  gq -f query='query($l:String!){ repositoryOwner(login:$l){
      ... on User { projectsV2(first:100){ nodes{ id number title } } }
      ... on Organization { projectsV2(first:100){ nodes{ id number title } } } } }' -f l="$1" \
  | python3 -c 'import json,sys
o=json.load(sys.stdin)["data"]["repositoryOwner"] or {}
for p in (o.get("projectsV2") or {}).get("nodes",[]): print(p["id"],p["number"],p["title"],sep="\t")'
}

ghr_issue_node() {
  gq -f query='query($u:URI!){ resource(url:$u){ ... on Issue { id } ... on PullRequest { id } } }' -f u="$1" --jq '.data.resource.id // empty'
}

ghr_repo_node() { gh api "repos/$1" --jq .node_id 2>/dev/null; }

ghr_add_item() {
  gq -f query='mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p,contentId:$c}){ item{ id } } }' \
     -f p="$1" -f c="$2" --jq .data.addProjectV2ItemById.item.id
}

ghr_field_meta() { # <pnode> <name> → fieldId<TAB>dataType<TAB>optionsJSON
  gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { fields(first:50){ nodes {
      ... on ProjectV2FieldCommon { id name dataType }
      ... on ProjectV2SingleSelectField { options { id name } } } } } } }' -f id="$1" \
  | python3 -c '
import json,sys
want=sys.argv[1]
for f in json.load(sys.stdin)["data"]["node"]["fields"]["nodes"]:
    if f and f.get("name")==want:
        print(f["id"], f.get("dataType",""), json.dumps(f.get("options",[]), ensure_ascii=False), sep="\t"); break' "$2"
}

ghr_set_field() { # <pnode> <item> <name> <value>
  local pnode="$1" item="$2" fname="$3" val="$4" meta fid ftype opts oid
  meta="$(ghr_field_meta "$pnode" "$fname")"; [ -n "$meta" ] || { ghr_log "field missing: $fname (probable cause: not created on this board) — run roadmap_bootstrap.sh"; return 5; }
  fid="$(printf '%s' "$meta" | cut -f1)"; ftype="$(printf '%s' "$meta" | cut -f2)"
  if [ "$ftype" = "SINGLE_SELECT" ]; then
    opts="$(printf '%s' "$meta" | cut -f3)"
    oid="$(printf '%s' "$opts" | python3 -c 'import json,sys
v=sys.argv[1]
for o in json.load(sys.stdin):
    if o["name"]==v: print(o["id"]); break' "$val")"
    [ -n "$oid" ] || { ghr_log "option missing: $fname=$val (available: $(printf '%s' "$opts" | python3 -c 'import json,sys;print(", ".join(o["name"] for o in json.load(sys.stdin)))')) — use a listed option or update the field options"; return 5; }
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){ projectV2Item{ id } } }' \
       -f p="$pnode" -f i="$item" -f f="$fid" -f o="$oid" >/dev/null
  elif [ "$ftype" = "DATE" ]; then
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$d:Date!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{date:$d}}){ projectV2Item{ id } } }' \
       -f p="$pnode" -f i="$item" -f f="$fid" -f d="$val" >/dev/null
  else # TEXT etc.
    gq -f query='mutation($p:ID!,$i:ID!,$f:ID!,$t:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{text:$t}}){ projectV2Item{ id } } }' \
       -f p="$pnode" -f i="$item" -f f="$fid" -f t="$val" >/dev/null
  fi
}
