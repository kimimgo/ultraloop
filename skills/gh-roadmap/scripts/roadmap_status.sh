#!/usr/bin/env bash
# roadmap_status.sh — native project status updates (ON_TRACK/AT_RISK/...). Board health signal (BP#3).
#   Separate from derived views like PROGRESS.md, leaves a native "is this roadmap on track" signal at the top of the GitHub board.
# usage:
#   roadmap_status.sh set <ON_TRACK|AT_RISK|OFF_TRACK|COMPLETE|INACTIVE> ["body"] [--target YYYY-MM-DD] [--start YYYY-MM-DD]
#   roadmap_status.sh list
# exit 0=ok · 2=argument error · 3=board not configured · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"
PNODE="$(cfg_get board.project_node_id "")"
[ -n "$PNODE" ] || { ghr_log "board.project_node_id not set (probable cause: board not bootstrapped) — run roadmap_bootstrap.sh first"; exit 3; }
CMD="${1:-}"; shift || true

case "$CMD" in
set)
  STATUS="${1:?usage: set <ON_TRACK|AT_RISK|OFF_TRACK|COMPLETE|INACTIVE> [body] [--target D]}"; shift || true
  case "$STATUS" in ON_TRACK|AT_RISK|OFF_TRACK|COMPLETE|INACTIVE) ;; *) ghr_log "invalid status: $STATUS — use one of ON_TRACK|AT_RISK|OFF_TRACK|COMPLETE|INACTIVE"; exit 2;; esac
  BODY=""; TARGET=""; START=""
  while [ $# -gt 0 ]; do case "$1" in
    --target) TARGET="$2"; shift 2;; --start) START="$2"; shift 2;;
    *) BODY="$1"; shift;; esac; done
  ARGS=(-f query='mutation($p:ID!,$s:ProjectV2StatusUpdateStatus!,$b:String,$t:Date,$st:Date){ createProjectV2StatusUpdate(input:{projectId:$p,status:$s,body:$b,targetDate:$t,startDate:$st}){ statusUpdate{ id status } } }'
        -f p="$PNODE" -f s="$STATUS")
  [ -n "$BODY" ]   && ARGS+=(-f b="$BODY")
  [ -n "$TARGET" ] && ARGS+=(-f t="$TARGET")
  [ -n "$START" ]  && ARGS+=(-f st="$START")
  gq "${ARGS[@]}" --jq '.data.createProjectV2StatusUpdate.statusUpdate | "✓ status update: \(.status) (\(.id))"' \
    || { ghr_log "createProjectV2StatusUpdate failed: $(head -1 /tmp/ghr_gq.err) (probable cause: token scopes or invalid board.project_node_id) — check the token scopes (project) and config"; exit 5; } ;;
list)
  RAW="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { statusUpdates(first:10){ nodes{ status startDate targetDate body createdAt } } } } }' -f id="$PNODE")"
  RAW="$RAW" python3 - <<'PY'
import json,os
u=((json.loads(os.environ["RAW"] or "{}").get("data") or {}).get("node") or {}).get("statusUpdates",{}).get("nodes",[])
if not u:
    print("(no status updates)"); raise SystemExit
for s in u:
    span=" ".join(x for x in [s.get("startDate") or "", "→", s.get("targetDate") or ""] if x.strip("→ "))
    date=(s.get("createdAt") or "")[:10]
    body=(s.get("body") or "").strip()[:120]
    print(f'[{date}] {s.get("status")}  {span}\n    {body}')
PY
  ;;
*) echo "usage: roadmap_status.sh set <STATUS> [body] [--target D] [--start D] | list"; exit 2 ;;
esac
