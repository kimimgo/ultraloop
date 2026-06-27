#!/usr/bin/env bash
# meta_sync.sh — N레포 메타 루프의 결정적 코어 (multi-repo-orchestration.md §4 ①)
#   assign    : 레포별 배정 가능 이슈(Ready상태 + blocked 라벨 없음 + depends_on 전부 충족) JSON lines.
#               교차 레포 Depends-on 게이트가 여기 산다 — 의존 토큰(O5, C3, CP-HB...)을 "보드 카드 제목의
#               선두 코드"로 해석하므로 레포 경계 무관. 해석 불가 토큰 = 미충족(안전 기본값).
#   rollup    : 레포별 섹션 + 전체 롤업 markdown (PROGRESS에 붙임).
#   reconcile : 이슈 상태 ⇄ 보드 카드 멱등 수렴(dan323/easier-life-skills gh-project-sync의 reconciler
#               패턴 차용, tasks.yml 미러는 SoT 위반이라 배제) — CLOSED인데 카드≠Done → Done으로 수렴(자동),
#               Done인데 이슈 OPEN → 경고만(이슈 close는 판단 필요·자동 금지). --dry-run 지원.
#   self-test : 네트워크 0 — 인메모리 픽스처를 UE_RAW로 주입해 assign/reconcile의 *실제 코드 경로*를 검증.
# usage:
#   meta_sync.sh assign [--verbose] | rollup | reconcile [--dry-run] | self-test
# exit 0=ok · 1=self-test 실패 · 3=보드 미설정 · 5=API 실패
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
MODE="${1:-assign}"; FLAG="${2:-}"
READY="$(cfg_get roadmap.ready_status Ready)"

if [ "$MODE" = "self-test" ]; then
  # ── 픽스처(가짜 보드) → 자기 자신을 UE_RAW_OVERRIDE로 재호출 → 실제 경로 검증 ──
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
  R="$(UE_RAW_OVERRIDE="$FIX" bash "${BASH_SOURCE[0]}" reconcile --dry-run 2>&1)"   # WARN은 stderr 설계 — 합쳐 캡처
  ok=0; fail=0
  [ "$A" = "[2, 3, 9]" ] && { echo "✓ assign = #2,#3,#9 (free+제목dep충족+네이티브dep충족; gated/blocked/done/native-blocked 제외)"; ok=$((ok+1)); } \
    || { echo "✗ assign 기대 [2, 3, 9], 실제 $A"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "SET_DONE u6" && { echo "✓ reconcile: CLOSED+Todo → SET_DONE"; ok=$((ok+1)); } \
    || { echo "✗ reconcile SET_DONE u6 누락: $R"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "WARN.*#7" && { echo "✓ reconcile: Done+OPEN → 경고만(자동 close 금지)"; ok=$((ok+1)); } \
    || { echo "✗ reconcile #7 경고 누락"; fail=$((fail+1)); }
  printf '%s' "$R" | grep -q "SET_DONE u1" && { echo "✗ 멱등 위반: 이미 Done인 u1 재수렴"; fail=$((fail+1)); } \
    || { echo "✓ reconcile 멱등: 이미 Done은 무시"; ok=$((ok+1)); }
  echo "self-test: $ok pass / $fail fail"; [ "$fail" = 0 ] || exit 1; exit 0
fi

# ── 보드 읽기 (self-test가 UE_RAW_OVERRIDE로 우회 주입) ─────────────────────
[ -n "${UE_READY_OVERRIDE:-}" ] && READY="$UE_READY_OVERRIDE"
if [ -n "${UE_RAW_OVERRIDE:-}" ]; then RAW="$UE_RAW_OVERRIDE"; else
  PNODE="$(cfg_get roadmap.project_node_id "")"
  TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
  [ -n "$PNODE" ] || { ue_log "roadmap.project_node_id 미설정"; exit 3; }
  # --paginate + $endCursor/pageInfo: 100+ 카드 보드도 전부 읽는다(누락 방지). 출력=페이지별 JSON 연결.
  RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){ node(id:$id){ ... on ProjectV2 { items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor } nodes {
      content{ ... on Issue { number title state body url repository{ nameWithOwner } labels(first:20){ nodes{ name } } blockedBy(first:20){ nodes{ number state } } } }
      fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue { name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' \
      -f id="$PNODE" 2>/tmp/ue_ms.err)" || { ue_log "보드 graphql 실패: $(head -1 /tmp/ue_ms.err)"; exit 5; }
fi

# ⚠️ 파이프+heredoc 동시 사용 금지 — heredoc이 stdin(스크립트)을 차지해 데이터가 유실된다. env로 전달.
OUT="$(UE_RAW="$RAW" python3 - "$MODE" "$READY" "$FLAG" <<'PY'
import json, re, sys, os, collections
mode, ready, flag = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
def _all_nodes(raw):
    # --paginate 출력은 페이지별 JSON이 연결돼 올 수 있다(단일 페이지·self-test 단일 JSON도 동일 처리).
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
    return False, tok[:30]  # 해석 불가(외부 게이트 등) = 미충족

if mode == "assign":
    for card in cards:
        if card["state"] != "OPEN" or card["status"].lower() != ready: continue
        if "blocked" in card["labels"]:
            if flag == "--verbose": print(f"GATED {card['repo']}#{card['number']} — blocked 라벨", file=sys.stderr)
            continue
        unmet = [name for ok, name in (dep_ok(t) for t in deps_of(card)) if not ok]
        native = [f"#{b['number']}" for b in card["blocked_by"] if b.get("state") != "CLOSED"]  # 네이티브 blocked-by(gh-roadmap) — blocker가 CLOSED여야 충족
        if unmet or native:
            if flag == "--verbose": print(f"GATED {card['repo']}#{card['number']} — 미충족 의존: {', '.join(unmet + native)}", file=sys.stderr)
            continue
        print(json.dumps({"repo": card["repo"], "number": card["number"],
                          "title": card["title"], "stage": card["stage"]}, ensure_ascii=False))
elif mode == "reconcile":
    # 멱등 수렴 계획: CLOSED인데 카드≠Done → SET_DONE(자동 적용 대상). Done인데 OPEN → 경고만.
    for card in cards:
        if card["state"] == "CLOSED" and card["status"] != "Done":
            print(f"SET_DONE {card['url']}")
        elif card["status"] == "Done" and card["state"] == "OPEN":
            print(f"WARN 카드 Done인데 이슈 OPEN — {card['repo']}#{card['number']} (이슈 close는 수동 판단)", file=sys.stderr)
        elif "blocked" in card["labels"] and card["status"] == "In-Progress":
            print(f"WARN blocked 라벨인데 In-Progress — {card['repo']}#{card['number']}", file=sys.stderr)
elif mode == "rollup":
    by_repo = collections.defaultdict(list)
    for card in cards: by_repo[card["repo"]].append(card)
    print(f"## N레포 롤업 (공유 보드 · 총 {len(cards)}카드)\n")
    for repo in sorted(by_repo):
        cs = by_repo[repo]
        st = collections.Counter((c["status"] or "(미설정)") for c in cs)
        blocked = sum(1 for c in cs if "blocked" in c["labels"])
        line = " · ".join(f"{k} {v}" for k, v in sorted(st.items()))
        print(f"### {repo} — {len(cs)}카드\n- 상태: {line}" + (f" · 🔒blocked {blocked}" if blocked else ""))
        for c in cs:
            if c["status"] == "In-Progress": print(f"  - ▶ #{c['number']} {c['title'][:60]}")
        print()
    total = collections.Counter((c["status"] or "(미설정)") for c in cards)
    print("**전체**: " + " · ".join(f"{k} {v}" for k, v in sorted(total.items())))
PY
)" || exit $?

if [ "$MODE" = "reconcile" ] && [ "$FLAG" != "--dry-run" ] && [ -z "${UE_RAW_OVERRIDE:-}" ]; then
  # 수렴 적용 — board.sh 재사용(쓰기 경로 단일화)
  printf '%s\n' "$OUT" | while read -r ACT URL; do
    [ "$ACT" = "SET_DONE" ] && [ -n "$URL" ] && bash "$SDIR/board.sh" status "$URL" Done
  done
  N=$(printf '%s\n' "$OUT" | grep -c "^SET_DONE" || true); ue_log "reconcile: ${N:-0}건 Done 수렴"
else
  printf '%s\n' "$OUT"
fi
