#!/usr/bin/env bash
# roadmap_sync.sh — 로드맵 게이트 + 다음 Ready 이슈 N개 산출.
#   exit 0 = 로드맵 있음+승인 → 다음 Ready 이슈를 stdout(JSON line)으로
#   exit 3 = 로드맵 없음 → 기획 제안 모드(SKILL §4)
#   exit 5 = 일시적 읽기 실패(API/네트워크) → 재시도/백오프 (기획 모드로 가지 말 것)
# ★ exit 3 vs 5 구분이 핵심: 네트워크 한 번 끊겼다고 멀쩡한 프로젝트를 리셋하면 안 된다.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; N="$(cfg_get worktree.max_lanes 2)"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
PROJ="$(cfg_get roadmap.project_number "")"
READY="$(cfg_get roadmap.ready_status Ready)"   # 보드 Status 옵션명(기본 Ready; GitHub 기본 보드는 Todo)
OWNER="${REPO%%/*}"

command -v gh >/dev/null 2>&1 || { ue_log "gh 없음"; exit 5; }
gh auth status >/dev/null 2>&1 || { ue_log "gh 인증 실패(일시?)"; exit 5; }

# 보드 미설정 — 폴백(R2, roadmap-model §6): provider=milestones면 이슈를 로드맵으로 사용
if [ -z "$PROJ" ]; then
  if [ "$(cfg_get roadmap.provider github_projects_v2)" = "milestones" ]; then
    if [ "$(cfg_get roadmap.approved false)" != "true" ]; then
      ue_log "로드맵 미승인(roadmap.approved!=true) → 기획 제안"; exit 3
    fi
    RAW="$(gh issue list -R "$REPO" --state open --limit 1000 --json number,title,labels 2>/tmp/ue_rs.err)"; RC=$?
    if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then ue_log "이슈 조회 일시 실패 → 재시도"; exit 5; fi
    # 다음 Ready 이슈 N개 = open 이슈 중 blocked 라벨 없는 것 (오케스트레이터가 최종 판단)
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
  ue_log "보드 미설정(project_number 없음)"; exit 3
fi

# gh 구버전(2.4.0 실측)엔 `gh project` 명령 부재 → graphql 직접 폴백 (multi-repo-orchestration.md §3).
# 공유 보드(board.shared=true)면 자기 레포 카드만 필터하고, 승인은 config roadmap.approved(메타가 기록)로 본다.
if ! gh project item-list --help >/dev/null 2>&1; then
  PNODE="$(cfg_get roadmap.project_node_id "")"
  [ -n "$PNODE" ] || { ue_log "gh project 부재 + project_node_id 미기록 → 보드 읽기 불가(부트스트랩/기록 필요)"; exit 3; }
  # --paginate + $endCursor/pageInfo: 100+ 카드 보드도 전부 읽는다(Ready 카드 누락 방지).
  RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh api graphql --paginate -f query='query($id:ID!,$endCursor:String){ node(id:$id){ ... on ProjectV2 { items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor } nodes {
      content{ ... on Issue { number title repository{ nameWithOwner } } }
      fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue { name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' \
      -f id="$PNODE" 2>/tmp/ue_rs.err)"; RC=$?
  if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then
    grep -qiE "NOT_FOUND|could not resolve" /tmp/ue_rs.err 2>/dev/null && { ue_log "보드 부재(node_id 무효)"; exit 3; }
    ue_log "보드 graphql 일시 실패 → 재시도: $(head -1 /tmp/ue_rs.err 2>/dev/null)"; exit 5
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
for it in [i for i in items if i["status"].lower()==ready][:N]:
    print(json.dumps(it, ensure_ascii=False))
' "$N" "$FILTER" "$APPROVED_OK" "$READY"
  RC=$?; [ "$RC" = 3 ] && { ue_log "로드맵 비었거나 미승인 → 기획 제안"; exit 3; }
  exit "$RC"
fi

# 보드 항목 조회. 네트워크/권한 실패와 '0건'을 구분한다.
RAW="$(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh project item-list "$PROJ" --owner "$OWNER" --format json 2>/tmp/ue_rs.err)"
RC=$?
if [ "$RC" -ne 0 ] || [ -z "$RAW" ]; then
  # 권한/네트워크/속도제한 → 일시 실패(재시도). 단 "프로젝트 없음" 메시지면 부재(3).
  if grep -qiE "could not resolve|not found|no project|does not exist" /tmp/ue_rs.err 2>/dev/null; then
    ue_log "보드 부재"; exit 3
  fi
  ue_log "보드 조회 일시 실패 → 재시도 권장: $(head -1 /tmp/ue_rs.err 2>/dev/null)"; exit 5
fi

# 승인 마커: roadmap:approved 라벨(assets/labels.json, 부트스트랩이 생성). 없으면 미시작 → 기획 제안.
APPROVED="$(gh issue list -R "$REPO" --label 'roadmap:approved' --state all --json number -q 'length' 2>/dev/null || echo 0)"
COUNT="$(printf '%s' "$RAW" | python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else []); print(len(items))
except Exception: print("ERR")' 2>/dev/null)"
[ "$COUNT" = "ERR" ] && { ue_log "보드 파싱 실패"; exit 5; }
if [ "${COUNT:-0}" -lt 1 ] || [ "${APPROVED:-0}" -lt 1 ]; then
  ue_log "로드맵 비었거나 미승인(items=$COUNT approved=$APPROVED) → 기획 제안"; exit 3
fi

# 다음 Ready 이슈 N개를 stdout(JSON lines). Depends-on/모듈충돌은 오케스트레이터가 최종 판단.
printf '%s' "$RAW" | python3 -c '
import json,sys
N=int(sys.argv[1]) if len(sys.argv)>1 else 2
ready_name=(sys.argv[2] if len(sys.argv)>2 else "Ready").lower()
d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
ready=[it for it in items if str(it.get("status","")).lower()==ready_name]
for it in ready[:N]:
    print(json.dumps({"title":it.get("title",""),"content":it.get("content",{}),"status":it.get("status","")}, ensure_ascii=False))
' "$N" "$READY"
exit 0
