#!/usr/bin/env bash
# roadmap_sync.sh — roadmap gate + produce the next N Ready issues.
#   exit 0 = roadmap exists + approved → next Ready issues on stdout (JSON lines)
#   exit 3 = no roadmap → planning-proposal mode (SKILL §4)
#   exit 5 = transient read failure (API/network) → retry/backoff (do NOT drop into planning mode)
# ★ The exit 3 vs 5 distinction is critical: one network hiccup must not reset a healthy project.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; N="$(cfg_get worktree.max_lanes 2)"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
PROJ="$(cfg_get roadmap.project_number "")"
READY="$(cfg_get roadmap.ready_status Ready)"   # board Status option name (default Ready; the GitHub default board uses Todo)
OWNER="${REPO%%/*}"

command -v gh >/dev/null 2>&1 || { ue_log "gh missing"; exit 5; }
gh auth status >/dev/null 2>&1 || { ue_log "gh auth failed (transient?)"; exit 5; }

# v0.10 run scope (engine.goal.scope=milestone:<title>): Ready collection narrows to that
# milestone so the loop never picks out-of-scope cards (goal_check enforces the same scope).
MS="$(ue_goal_scope 2>/dev/null || true)"
UE_MS_SCOPED=0; UE_MS_ALLOWED=""
if [ -n "$MS" ]; then
  UE_MS_SCOPED=1
  UE_MS_ALLOWED="$(gh issue list -R "$REPO" --milestone "$MS" --state open --limit 1000 --json number -q 'map(.number|tostring)|join(",")' 2>/dev/null)"
  ue_log "run scope: milestone \"$MS\" ($( [ -n "$UE_MS_ALLOWED" ] && printf '%s' "$UE_MS_ALLOWED" | awk -F, '{print NF}' || echo 0 ) open issues)"
fi
export UE_MS_SCOPED UE_MS_ALLOWED

# Board not configured — fallback (R2, roadmap-model §6): if provider=milestones, use issues as the roadmap
if [ -z "$PROJ" ]; then
  if [ "$(cfg_get roadmap.provider github_projects_v2)" = "milestones" ]; then
    if [ "$(cfg_get roadmap.approved false)" != "true" ]; then
      ue_log "roadmap not approved (roadmap.approved!=true) → planning proposal"; exit 3
    fi
    MSARG=(); [ -n "$MS" ] && MSARG=(--milestone "$MS")
    RAW="$(gh issue list -R "$REPO" "${MSARG[@]}" --state open --limit 1000 --json number,title,labels 2>/tmp/ue_rs.err)"; RC=$?
    if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then ue_log "issue query transient failure → retry"; exit 5; fi
    # Next N Ready issues = open issues without the blocked label (the orchestrator makes the final call)
    printf '%s' "$RAW" | python3 -c '
import json,sys
N=int(sys.argv[1]) if len(sys.argv)>1 else 2
items=json.load(sys.stdin)
ready=[it for it in items if not any(l.get("name")=="blocked" for l in it.get("labels",[]))]
for it in ready[:N]:
    print(json.dumps({"number":it["number"],"title":it["title"],"status":"open"}, ensure_ascii=False))
' "$N"
    exit 0
  fi
  ue_log "board not configured (no project_number)"; exit 3
fi

# Old gh (2.4.0 observed) lacks the `gh project` command → direct graphql fallback.
# On a shared board (board.shared=true — one board spanning N repos), filter to own-repo cards only.
if ! gh project item-list --help >/dev/null 2>&1; then
  PNODE="$(cfg_get roadmap.project_node_id "")"
  [ -n "$PNODE" ] || { ue_log "gh project absent + project_node_id not recorded → cannot read board (bootstrap/record needed)"; exit 3; }
  # --paginate + $endCursor/pageInfo: reads boards with 100+ cards in full (prevents missing Ready cards).
  RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){ node(id:$id){ ... on ProjectV2 { items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor } nodes {
      content{ ... on Issue { number title repository{ nameWithOwner } } }
      fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue { name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' \
      -f id="$PNODE" 2>/tmp/ue_rs.err)"; RC=$?
  if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then
    grep -qiE "NOT_FOUND|could not resolve" /tmp/ue_rs.err 2>/dev/null && { ue_log "board absent (node_id invalid)"; exit 3; }
    ue_log "board graphql transient failure → retry: $(head -1 /tmp/ue_rs.err 2>/dev/null)"; exit 5
  fi
  FILTER=""; [ "$(cfg_get board.shared false)" = "true" ] && FILTER="$REPO"
  if [ -n "$FILTER" ]; then APPROVED_OK="$(cfg_get roadmap.approved false)"; else
    A="$(gh issue list -R "$REPO" --label 'roadmap:approved' --state all --json number -q 'length' 2>/dev/null || echo 0)"
    APPROVED_OK="false"; [ "${A:-0}" -ge 1 ] && APPROVED_OK="true"
  fi
  printf '%s' "$RAW" | python3 -c '
import json,sys
N=int(sys.argv[1]); FILTER=sys.argv[2]; approved=sys.argv[3]=="true"
def _all(raw):
    dec=json.JSONDecoder(); i=0; out=[]; raw=raw.strip()
    while i<len(raw):
        o,i=dec.raw_decode(raw,i)
        out+=((((o.get("data",{}) or {}).get("node") or {}).get("items",{}) or {}).get("nodes") or [])
        while i<len(raw) and raw[i] in " \t\r\n": i+=1
    return out
nodes=_all(sys.stdin.read())
items=[]
for it in nodes:
    c=it.get("content") or {}
    repo=(c.get("repository") or {}).get("nameWithOwner","")
    if FILTER and repo!=FILTER: continue
    status=""
    for fv in ((it.get("fieldValues") or {}).get("nodes") or []):
        if fv and (fv.get("field") or {}).get("name")=="Status": status=fv.get("name","")
    items.append({"number":c.get("number"),"title":c.get("title",""),"status":status,"repo":repo})
if not items or not approved:
    print(f"EXIT3 items={len(items)} approved={approved}", file=sys.stderr); sys.exit(3)
ready=sys.argv[4].lower()
import os
scoped=os.environ.get("UE_MS_SCOPED")=="1"
allowed=set(x for x in os.environ.get("UE_MS_ALLOWED","").split(",") if x)
def in_scope(i): return (not scoped) or (str(i.get("number")) in allowed)
for it in [i for i in items if i["status"].lower()==ready and in_scope(i)][:N]:
    print(json.dumps(it, ensure_ascii=False))
' "$N" "$FILTER" "$APPROVED_OK" "$READY"
  RC=$?; [ "$RC" = 3 ] && { ue_log "roadmap empty or not approved → planning proposal"; exit 3; }
  exit "$RC"
fi

# Query board items. Distinguish network/permission failures from "0 items".
RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh project item-list "$PROJ" --owner "$OWNER" --format json 2>/tmp/ue_rs.err)"
RC=$?
if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then
  # Permission/network/rate-limit → transient failure (retry). But a "project missing" message means absent (3).
  if grep -qiE "could not resolve|not found|no project|does not exist" /tmp/ue_rs.err 2>/dev/null; then
    ue_log "board absent"; exit 3
  fi
  ue_log "board query transient failure → retry recommended: $(head -1 /tmp/ue_rs.err 2>/dev/null)"; exit 5
fi

# Approval marker: roadmap:approved label (assets/labels.json, created by bootstrap). Absent means not started → planning proposal.
APPROVED="$(gh issue list -R "$REPO" --label 'roadmap:approved' --state all --json number -q 'length' 2>/dev/null || echo 0)"
COUNT="$(printf '%s' "$RAW" | python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else []); print(len(items))
except Exception: print("ERR")' 2>/dev/null)"
[ "$COUNT" = "ERR" ] && { ue_log "board parse failed"; exit 5; }
if [ "${COUNT:-0}" -lt 1 ] || [ "${APPROVED:-0}" -lt 1 ]; then
  ue_log "roadmap empty or not approved (items=$COUNT approved=$APPROVED) → planning proposal"; exit 3
fi

# Next N Ready issues to stdout (JSON lines). Depends-on/module conflicts are the orchestrator final call.
printf '%s' "$RAW" | python3 -c '
import json,sys
N=int(sys.argv[1]) if len(sys.argv)>1 else 2
ready_name=(sys.argv[2] if len(sys.argv)>2 else "Ready").lower()
d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
import os
scoped=os.environ.get("UE_MS_SCOPED")=="1"
allowed=set(x for x in os.environ.get("UE_MS_ALLOWED","").split(",") if x)
def in_scope(it): return (not scoped) or (str((it.get("content") or {}).get("number")) in allowed)
ready=[it for it in items if str(it.get("status","")).lower()==ready_name and in_scope(it)]
for it in ready[:N]:
    print(json.dumps({"title":it.get("title",""),"content":it.get("content",{}),"status":it.get("status","")}, ensure_ascii=False))
' "$N" "$READY"
exit 0
