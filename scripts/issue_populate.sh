#!/usr/bin/env bash
# issue_populate.sh — idempotency and concurrency guard for bulk board/issue creation (directly motivated by the 2026-06-11 OCMS duplicate-issue race)
#   ① population lock: GitHub-side lock (marker issue) — a local lock is powerless across sessions. Blocks the accident
#      where multiple cc sessions turn the same plan into issues at once. ② ensure: title-normalized query-then-create —
#      treats "[O1] foo" and "O1 foo" as the same card and filters out duplicate creation (compare after stripping the leading code token).
# usage:
#   issue_populate.sh lock   [<repo>] [--ttl-minutes 30]   # exit 0=acquired/stale takeover · 4=held by another session (abort)
#   issue_populate.sh unlock [<repo>]
#   issue_populate.sh ensure <repo> <title> [--body-file F] [--label L ...]
#       → existing match: prints "SKIP #n", new: prints "CREATED #n <url>". Both exit 0. Failure exit 5.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
LOCK_TITLE="ultraloop: population-lock"
HOLDER="${ULTRALOOP_HOLDER:-$(hostname)-$$}"

norm() { # title normalization: strip the leading code token ([O1]/O1/CP-HB/T001 etc — uppercase, digits, hyphens), then lowercase and collapse whitespace
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
  [ -n "$REPO" ] || { echo "✗ repo not resolved — no git remote or config found; pass <repo> explicitly or run inside a repo"; exit 5; }
  # ⚠️ --search (the search API) misses a just-created lock due to indexing lag (measured) — use plain list only for locking.
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
      ue_log "population lock held by another session (#$NUM, ${AGE_MIN}m < TTL ${TTL}m) — stop issue creation"; exit 4
    fi
    gh issue comment "$NUM" -R "$REPO" -b "lock renewed/taken over: holder=$HOLDER" >/dev/null 2>&1
    echo "LOCKED #$NUM (re-acquired/stale takeover)"; exit 0
  fi
  URL="$(gh issue create -R "$REPO" -t "$LOCK_TITLE" \
        -b "Lock while bulk board/issue creation is in progress. holder=$HOLDER · TTL ${TTL}m. Unlock (close) when done." 2>/dev/null)" \
    || { ue_log "lock issue creation failed — check gh auth and repo write access, then retry"; exit 5; }
  echo "LOCKED #${URL##*/}" ;;

unlock)
  REPO="${1:-$(ue_repo)}"
  NUM="$(gh issue list -R "$REPO" --state open --limit 100 --json number,title 2>/dev/null \
        | python3 -c 'import json,sys
for it in json.load(sys.stdin) or []:
    if it["title"].strip()==sys.argv[1]: print(it["number"]); break' "$LOCK_TITLE")"
  [ -n "$NUM" ] && gh issue close "$NUM" -R "$REPO" >/dev/null 2>&1 && echo "UNLOCKED #$NUM" || echo "no lock (already released)" ;;

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
  if [ -n "$MATCH" ]; then echo "SKIP #$MATCH (normalized title match — duplicate creation prevented)"; exit 0; fi
  BODY=""; [ -n "$BODYF" ] && BODY="$(cat "$BODYF" 2>/dev/null)"   # --body-file is absent in old gh (2.4) → pass via -b
  URL="$(gh issue create -R "$REPO" -t "$TITLE" -b "$BODY" "${LABELS[@]}" 2>/dev/null)" || { ue_log "creation failed: $TITLE — check gh auth, repo access, and that the labels exist"; exit 5; }
  echo "CREATED #${URL##*/} $URL" ;;

*) echo "usage: issue_populate.sh lock|unlock|ensure ..."; exit 5 ;;
esac
