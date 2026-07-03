#!/usr/bin/env bash
# meta_sync.sh — deterministic core of the N-repo meta loop (multi-repo-orchestration.md §4 ①)
#   assign    : JSON lines of assignable issues per repo (Ready status + no blocked label + all depends_on met).
#               The cross-repo Depends-on gate lives here — dependency tokens (O5, C3, CP-HB...) are resolved as
#               "leading codes in board card titles", so repo boundaries do not matter. Unresolvable token = unmet (safe default).
#   rollup    : per-repo sections + overall rollup markdown (appended to PROGRESS).
#   reconcile : idempotent convergence of issue state ⇄ board card (borrows the reconciler pattern of
#               dan323/easier-life-skills gh-project-sync; a tasks.yml mirror violates SoT so it is excluded) —
#               CLOSED but card≠Done → converge to Done (automatic), Done but issue OPEN → warn only
#               (closing the issue needs judgment; auto close forbidden). Supports --dry-run.
#   self-test : zero network — injects an in-memory fixture via UE_RAW to verify the *actual code paths* of assign/reconcile.
# usage:
#   meta_sync.sh assign [--verbose] | rollup | reconcile [--dry-run] | self-test
# exit 0=ok · 1=self-test failed · 3=board not configured · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
MODE="${1:-assign}"; FLAG="${2:-}"
READY="$(cfg_get roadmap.ready_status Ready)"

if [ "$MODE" = "self-test" ]; then
  # ── fixture (fake board) → re-invoke self with UE_RAW_OVERRIDE → verify real paths ──
  FIX='{"data":{"node":{"items":{"nodes":[
    {"content":{"number":1,"title":"A1 done base","state":"CLOSED","body":"depends_on: —","url":"u1","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Done","field":{"name":"Status"}}]}},
    {"content":{"number":2,"title":"B1 ready free","state":"OPEN","body":"depends_on: —","url":"u2","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":3,"title":"C1 dep met","state":"OPEN","body":"depends_on: A1 (#1)","url":"u3","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":4,"title":"D1 dep unmet","state":"OPEN","body":"depends_on: B1 (#2)","url":"u4","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":5,"title":"E1 blocked","state":"OPEN","body":"depends_on: —","url":"u5","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[{"name":"blocked"}]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":6,"title":"F1 closed todo","state":"CLOSED","body":"depends_on: —","url":"u6","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":7,"title":"G1 done open","state":"OPEN","body":"depends_on: —","url":"u7","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Done","field":{"name":"Status"}}]}},
    {"content":{"number":8,"title":"H1 native-blocked","state":"OPEN","body":"depends_on: —","url":"u8","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]},"blockedBy":{"nodes":[{"number":2,"state":"OPEN"}]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}},
    {"content":{"number":9,"title":"I1 native-ok","state":"OPEN","body":"depends_on: —","url":"u9","repository":{"nameWithOwner":"o/r"},"labels":{"nodes":[]},"blockedBy":{"nodes":[{"number":1,"state":"CLOSED"}]}},"fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]}}
  ]}}}}'
  A="$(UE_RAW_OVERRIDE="$FIX" UE_READY_OVERRIDE=Todo bash "${BASH_SOURCE[0]}" assign 2>/dev/null \
      | python3 -c 'import json,sys; print(sorted(json.loads(l)["number"] for l in sys.stdin))')"
  R="$(UE_RAW_OVERRIDE="$FIX" bash "${BASH_SOURCE[0]}" reconcile --dry-run 2>&1)"   # WARN goes to stderr by design — capture combined
  ok=0; fail=0
  [ "$A" = "[2, 3, 9]" ] && { echo "✓ assign = #2,#3,#9 (free + title-dep met + native-dep met; gated/blocked/done/native-blocked excluded)"; ok=$((ok+1)); } \
    || { echo "✗ assign expected [2, 3, 9], got $A"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "SET_DONE u6" && { echo "✓ reconcile: CLOSED+Todo → SET_DONE"; ok=$((ok+1)); } \
    || { echo "✗ reconcile SET_DONE u6 missing: $R"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "WARN.*#7" && { echo "✓ reconcile: Done+OPEN → warn only (auto close forbidden)"; ok=$((ok+1)); } \
    || { echo "✗ reconcile #7 warning missing"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "SET_DONE u1" && { echo "✗ idempotency violation: u1 already Done was reconverged"; fail=$((fail+1)); } \
    || { echo "✓ reconcile idempotent: already-Done is ignored"; ok=$((ok+1)); }
  echo "self-test: $ok pass / $fail fail"; [ "$fail" = 0 ] || exit 1; exit 0
fi

# ── read the board (self-test bypasses by injecting UE_RAW_OVERRIDE) ─────────────────
[ -n "${UE_READY_OVERRIDE:-}" ] && READY="$UE_READY_OVERRIDE"
if [ -n "${UE_RAW_OVERRIDE:-}" ]; then RAW="$UE_RAW_OVERRIDE"; else
  PNODE="$(cfg_get roadmap.project_node_id "")"
  TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
  [ -n "$PNODE" ] || { ue_log "roadmap.project_node_id not set"; exit 3; }
  # --paginate + $endCursor/pageInfo: reads boards with 100+ cards in full (prevents omissions). Output = concatenated per-page JSON.
  RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){ node(id:$id){ ... on ProjectV2 { items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor } nodes {
      content{ ... on Issue { number title state body url repository{ nameWithOwner } labels(first:20){ nodes{ name } } blockedBy(first:20){ nodes{ number state } } } }
      fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue { name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' \
      -f id="$PNODE" 2>/tmp/ue_ms.err)" || { ue_log "board graphql failed: $(head -1 /tmp/ue_ms.err)"; exit 5; }
fi

# ⚠️ Never combine a pipe with a heredoc — the heredoc takes over stdin (the script) and data is lost. Pass via env.
OUT="$(UE_RAW="$RAW" python3 - "$MODE" "$READY" "$FLAG" <<'PY'
import json, re, sys, os, collections
mode, ready, flag = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
def _all_nodes(raw):
    # --paginate output may arrive as concatenated per-page JSON (single page and the self-test single JSON are handled the same).
    dec = json.JSONDecoder(); i = 0; out = []; raw = raw.strip()
    while i < len(raw):
        obj, i = dec.raw_decode(raw, i)
        items = ((obj.get("data", {}) or {}).get("node") or {}).get("items", {}) or {}
        out += (items.get("nodes") or [])
        while i < len(raw) and raw[i] in " \t\r\n": i += 1
    return out
nodes = _all_nodes(os.environ["UE_RAW"])
cards, by_code = [], {}
for it in nodes:
    c = it.get("content") or {}
    if not c.get("number"): continue
    fv = {(f.get("field") or {}).get("name"): f.get("name")
          for f in ((it.get("fieldValues") or {}).get("nodes") or []) if f}
    card = {"repo": (c.get("repository") or {}).get("nameWithOwner",""),
            "number": c["number"], "title": c.get("title",""), "state": c.get("state",""),
            "url": c.get("url",""), "status": fv.get("Status",""), "stage": fv.get("Stage",""),
            "labels": [l["name"] for l in ((c.get("labels") or {}).get("nodes") or [])],
            "blocked_by": [b for b in ((c.get("blockedBy") or {}).get("nodes") or [])],
            "body": c.get("body","")}
    m = re.match(r"^\[?([A-Z][A-Z0-9-]{0,15})\]?\s", card["title"])
    if m: by_code[m.group(1)] = card
    cards.append(card)

def done(card): return card["state"] == "CLOSED" or card["status"] == "Done"
def deps_of(card):
    m = re.search(r"^depends_on:\s*(.+)$", card["body"], re.M)
    if not m or m.group(1).strip() in ("—","-",""): return []
    return [t.strip() for t in m.group(1).split(",") if t.strip()]
def dep_ok(tok):
    m = re.match(r"^\[?([A-Z][A-Z0-9-]{0,15})\b", tok)
    if m and m.group(1) in by_code: return done(by_code[m.group(1)]), m.group(1)
    return False, tok[:30]  # unresolvable (external gate etc.) = unmet

if mode == "assign":
    for card in cards:
        if card["state"] != "OPEN" or card["status"].lower() != ready: continue
        if "blocked" in card["labels"]:
            if flag == "--verbose": print(f"GATED {card['repo']}#{card['number']} — blocked label", file=sys.stderr)
            continue
        unmet = [name for ok, name in (dep_ok(t) for t in deps_of(card)) if not ok]
        native = [f"#{b['number']}" for b in card["blocked_by"] if b.get("state") != "CLOSED"]  # native blocked-by (gh-roadmap) — met only when the blocker is CLOSED
        if unmet or native:
            if flag == "--verbose": print(f"GATED {card['repo']}#{card['number']} — unmet deps: {', '.join(unmet + native)}", file=sys.stderr)
            continue
        print(json.dumps({"repo": card["repo"], "number": card["number"],
                          "title": card["title"], "stage": card["stage"]}, ensure_ascii=False))
elif mode == "reconcile":
    # Idempotent convergence plan: CLOSED but card≠Done → SET_DONE (auto-apply target). Done but OPEN → warn only.
    for card in cards:
        if card["state"] == "CLOSED" and card["status"] != "Done":
            print(f"SET_DONE {card['url']}")
        elif card["status"] == "Done" and card["state"] == "OPEN":
            print(f"WARN card Done but issue OPEN — {card['repo']}#{card['number']} (issue close is a manual call)", file=sys.stderr)
        elif "blocked" in card["labels"] and card["status"] == "In-Progress":
            print(f"WARN blocked label but In-Progress — {card['repo']}#{card['number']}", file=sys.stderr)
elif mode == "rollup":
    by_repo = collections.defaultdict(list)
    for card in cards: by_repo[card["repo"]].append(card)
    print(f"## N-repo rollup (shared board · {len(cards)} cards total)\n")
    for repo in sorted(by_repo):
        cs = by_repo[repo]
        st = collections.Counter((c["status"] or "(unset)") for c in cs)
        blocked = sum(1 for c in cs if "blocked" in c["labels"])
        line = " · ".join(f"{k} {v}" for k, v in sorted(st.items()))
        print(f"### {repo} — {len(cs)} cards\n- status: {line}" + (f" · 🔒blocked {blocked}" if blocked else ""))
        for c in cs:
            if c["status"] == "In-Progress": print(f"  - ▶ #{c['number']} {c['title'][:60]}")
        print()
    total = collections.Counter((c["status"] or "(unset)") for c in cards)
    print("**Total**: " + " · ".join(f"{k} {v}" for k, v in sorted(total.items())))
PY
)" || exit $?

if [ "$MODE" = "reconcile" ] && [ "$FLAG" != "--dry-run" ] && [ -z "${UE_RAW_OVERRIDE:-}" ]; then
  # Apply convergence — reuse board.sh (single write path)
  printf '%s\n' "$OUT" | while read -r ACT URL; do
    [ "$ACT" = "SET_DONE" ] && [ -n "$URL" ] && bash "$SDIR/board.sh" status "$URL" Done
  done
  N=$(printf '%s\n' "$OUT" | grep -c "^SET_DONE" || true); ue_log "reconcile: ${N:-0} items converged to Done"
else
  printf '%s\n' "$OUT"
fi
