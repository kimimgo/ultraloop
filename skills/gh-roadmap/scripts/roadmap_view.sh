#!/usr/bin/env bash
# roadmap_view.sh — reads the board views/workflows/fields and verifies the golden template was applied correctly.
#   Views and workflows cannot be created via the API but can be read → an unattended skill can check the setup state and warn.
# usage: roadmap_view.sh check
# exit 0=ok · 3=board not configured · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"
PNODE="$(cfg_get board.project_node_id "")"
[ -n "$PNODE" ] || { ghr_log "board.project_node_id not set (probable cause: board not bootstrapped) — run roadmap_bootstrap.sh first"; exit 3; }

RAW="$(gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 {
    title url
    views(first:20){ nodes{ name number layout } }
    workflows(first:20){ nodes{ name number enabled } }
    fields(first:50){ nodes{ ... on ProjectV2FieldCommon { name dataType } } } } } }' -f id="$PNODE")"
[ -n "$RAW" ] || { ghr_log "check failed: $(head -1 /tmp/ghr_gq.err) (probable cause: invalid board.project_node_id or token scopes) — verify the config and token"; exit 5; }
RAW="$RAW" python3 - <<'PY'
import json,os
n=(json.loads(os.environ["RAW"]).get("data") or {}).get("node")
if not n:
    print("board read failed — check node_id/token"); raise SystemExit(5)
print(f'# {n["title"]}  {n["url"]}\n')
views=(n.get("views") or {}).get("nodes",[])
layouts={v["layout"] for v in views}
print(f'## Views ({len(views)})')
for v in views:
    print(f'  - {v["name"]}  [{v["layout"]}]')
print("  ✓ ROADMAP_LAYOUT present — long/mid-term timeline display available" if "ROADMAP_LAYOUT" in layouts
      else "  ⚠️ ROADMAP_LAYOUT missing — roadmap views cannot be created via API. Copy the golden template (board.template_node_id) or add the view once in the UI (references/golden-template-setup.md)")
wf=(n.get("workflows") or {}).get("nodes",[])
print(f'\n## Workflows ({len(wf)})')
for w in wf:
    state="✓ enabled" if w["enabled"] else "✗ disabled"
    print(f'  - {w["name"]}  {state}')
done_on=[w for w in wf if any(k in w["name"].lower() for k in ("close","merge","done"))]
if done_on and all(not w["enabled"] for w in done_on):
    print("  ⚠️ close/merge→Done workflows disabled — enable them in the UI to avoid manual reconcile work")
flds=[f for f in (n.get("fields") or {}).get("nodes",[]) if f]
names={f["name"] for f in flds}
print(f'\n## Fields ({len(flds)})')
for f in flds:
    print(f'  - {f["name"]}  ({f["dataType"]})')
miss=[x for x in ("Horizon","Target Date","Status") if x not in names]
print("  ⚠️ missing fields: "+", ".join(miss)+" — rerun roadmap_bootstrap.sh" if miss else "  ✓ core fields (Horizon·Target Date·Status) all present")
PY
