#!/usr/bin/env bash
# issue_populate.sh — 보드/이슈 대량 생성의 멱등·동시성 가드 (2026-06-11 OCMS 이중 이슈화 레이스가 직접 동기)
#   ① population lock: GitHub-측 잠금(마커 이슈) — 로컬 lock은 세션 간 무력. 다중 cc가 같은 계획을
#      동시에 이슈화하는 사고를 차단한다. ② ensure: 제목 정규화 query-then-create — "[O1] foo"와
#      "O1 foo"를 같은 카드로 보고 중복 생성을 거른다(코드 접두 토큰 제거 후 비교).
# usage:
#   issue_populate.sh lock   [<repo>] [--ttl-minutes 30]   # exit 0=획득/스테일 인수 · 4=타 세션 보유(중단하라)
#   issue_populate.sh unlock [<repo>]
#   issue_populate.sh ensure <repo> <title> [--body-file F] [--label L ...]
#       → 기존 매치: "SKIP #n" 출력, 신규: "CREATED #n <url>" 출력. 둘 다 exit 0. 실패 exit 5.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
LOCK_TITLE="ultraloop: population-lock"
HOLDER="${ULTRALOOP_HOLDER:-$(hostname)-$$}"

norm() { # 제목 정규화: 선두 코드 토큰([O1]/O1/CP-HB/T001 등 대문자·숫자·하이픈)을 떼고 소문자·공백 압축
  python3 -c '
import re,sys
t=sys.argv[1].strip()
t=re.sub(r"^\[?[A-Z][A-Z0-9-]{0,15}\]?[ :.]+","",t)
print(re.sub(r"\s+"," ",t).lower().strip())' "$1"
}

cmd="${1:-}"; shift || true
case "$cmd" in
lock)
  REPO="${1:-$(ue_repo)}"; TTL=30
  [ "${2:-}" = "--ttl-minutes" ] && TTL="${3:-30}"
  [ -n "$REPO" ] || { echo "✗ repo 미해석"; exit 5; }
  # ⚠️ --search(검색 API)는 인덱싱 지연으로 방금 생성된 lock을 못 본다(실측) — 잠금엔 일반 list만.
  EXIST="$(gh issue list -R "$REPO" --state open --limit 100 \
           --json number,title,updatedAt,body 2>/dev/null)"
  read -r NUM AGE_MIN OTHER <<<"$(printf '%s' "$EXIST" | python3 -c '
import json,sys,datetime
holder=sys.argv[1]; title=sys.argv[2]
now=datetime.datetime.now(datetime.timezone.utc)
for it in json.load(sys.stdin) or []:
    if it["title"].strip()==title:
        age=(now-datetime.datetime.fromisoformat(it["updatedAt"].replace("Z","+00:00"))).total_seconds()/60
        other = "1" if holder not in it.get("body","") else "0"
        print(it["number"], int(age), other); break
else: print("", "", "")' "$HOLDER" "$LOCK_TITLE")"
  if [ -n "${NUM:-}" ]; then
    if [ "${OTHER:-1}" = "1" ] && [ "${AGE_MIN:-0}" -lt "$TTL" ]; then
      ue_log "population lock 타 세션 보유(#$NUM, ${AGE_MIN}m < TTL ${TTL}m) — 이슈화 중단하라"; exit 4
    fi
    gh issue comment "$NUM" -R "$REPO" -b "lock 갱신/인수: holder=$HOLDER" >/dev/null 2>&1
    echo "LOCKED #$NUM (재획득/스테일 인수)"; exit 0
  fi
  URL="$(gh issue create -R "$REPO" -t "$LOCK_TITLE" \
        -b "보드/이슈 대량 생성 진행 중 잠금. holder=$HOLDER · TTL ${TTL}m. 완료 시 unlock(close)." 2>/dev/null)" \
    || { ue_log "lock 이슈 생성 실패"; exit 5; }
  echo "LOCKED #${URL##*/}" ;;

unlock)
  REPO="${1:-$(ue_repo)}"
  NUM="$(gh issue list -R "$REPO" --state open --limit 100 --json number,title 2>/dev/null \
        | python3 -c 'import json,sys
for it in json.load(sys.stdin) or []:
    if it["title"].strip()==sys.argv[1]: print(it["number"]); break' "$LOCK_TITLE")"
  [ -n "$NUM" ] && gh issue close "$NUM" -R "$REPO" >/dev/null 2>&1 && echo "UNLOCKED #$NUM" || echo "lock 없음(이미 해제)" ;;

ensure)
  REPO="${1:-}"; TITLE="${2:-}"; shift 2 || true
  [ -n "$REPO" ] && [ -n "$TITLE" ] || { echo "usage: ensure <repo> <title> [--body-file F] [--label L ...]"; exit 5; }
  BODYF=""; LABELS=()
  while [ $# -gt 0 ]; do case "$1" in
    --body-file) BODYF="$2"; shift 2;; --label) LABELS+=("--label" "$2"); shift 2;; *) shift;; esac; done
  WANT="$(norm "$TITLE")"
  MATCH="$(gh issue list -R "$REPO" --state open --limit 200 --json number,title 2>/dev/null \
          | python3 -c '
import json,re,sys
def norm(t):
    t=re.sub(r"^\[?[A-Z][A-Z0-9-]{0,15}\]?[ :.]+","",t.strip())
    return re.sub(r"\s+"," ",t).lower().strip()
want=sys.argv[1]
for it in json.load(sys.stdin) or []:
    if norm(it["title"])==want: print(it["number"]); break' "$WANT")"
  if [ -n "$MATCH" ]; then echo "SKIP #$MATCH (정규화 제목 일치 — 중복 생성 방지)"; exit 0; fi
  BODY=""; [ -n "$BODYF" ] && BODY="$(cat "$BODYF" 2>/dev/null)"   # --body-file은 gh 구버전(2.4) 부재 → -b로
  URL="$(gh issue create -R "$REPO" -t "$TITLE" -b "$BODY" "${LABELS[@]}" 2>/dev/null)" || { ue_log "생성 실패: $TITLE"; exit 5; }
  echo "CREATED #${URL##*/} $URL" ;;

*) echo "usage: issue_populate.sh lock|unlock|ensure ..."; exit 5 ;;
esac
