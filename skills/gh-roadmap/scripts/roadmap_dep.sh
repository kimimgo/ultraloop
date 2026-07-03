#!/usr/bin/env bash
# roadmap_dep.sh — native issue dependencies (blocked-by). Replaces title-regex and TEXT-field workarounds (works across repo boundaries).
# usage:
#   roadmap_dep.sh add  <blocked-url> <blocking-url>   # blocked is blocked by blocking
#   roadmap_dep.sh rm   <blocked-url> <blocking-url>
#   roadmap_dep.sh list <issue-url>                    # blockedBy + summary
# exit 0=ok · 2=argument error · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"
CMD="${1:-}"; shift || true

case "$CMD" in
add|rm)
  BLOCKED="${1:?usage: $CMD <blocked-url> <blocking-url>}"; BLOCKING="${2:?blocking-url required}"
  IB="$(ghr_issue_node "$BLOCKED")"; IK="$(ghr_issue_node "$BLOCKING")"
  [ -n "$IB" ] && [ -n "$IK" ] || { ghr_log "issue node resolution failed (probable cause: URL is not an issue/PR or the token lacks access) — verify both issue URLs and token scopes"; exit 5; }
  if [ "$CMD" = add ]; then
    gq -f query='mutation($i:ID!,$b:ID!){ addBlockedBy(input:{issueId:$i,blockingIssueId:$b}){ issue{ number } } }' \
       -f i="$IB" -f b="$IK" >/dev/null 2>&1 && echo "✓ $BLOCKED  ⟵blocked by⟵  $BLOCKING" \
       || { ghr_log "addBlockedBy failed: $(head -1 /tmp/ghr_gq.err) (probable cause: token scopes or issue access) — check token scopes (project, repo) and retry"; exit 5; }
  else
    gq -f query='mutation($i:ID!,$b:ID!){ removeBlockedBy(input:{issueId:$i,blockingIssueId:$b}){ issue{ number } } }' \
       -f i="$IB" -f b="$IK" >/dev/null 2>&1 && echo "✓ dependency removed: $BLOCKED ⟵ $BLOCKING" \
       || { ghr_log "removeBlockedBy failed: $(head -1 /tmp/ghr_gq.err) (probable cause: dependency does not exist or token scopes) — run roadmap_dep.sh list to check current dependencies"; exit 5; }
  fi ;;
list)
  URL="${1:?usage: list <issue-url>}"
  RAW="$(gq -f query='query($u:URI!){ resource(url:$u){ ... on Issue {
      number title
      blockedBy(first:50){ totalCount nodes{ number title state repository{ nameWithOwner } } } } } }' -f u="$URL")"
  RAW="$RAW" python3 - <<'PY'
import json,os
r=(json.loads(os.environ["RAW"] or "{}").get("data") or {}).get("resource")
if not r:
    print("not an issue or resolution failed — verify the issue URL"); raise SystemExit
bb=r.get("blockedBy") or {}
print(f'#{r["number"]} {r["title"]}')
print(f'  blocked by ({bb.get("totalCount",0)}):')
for n in bb.get("nodes",[]):
    mark="✓" if n.get("state")=="CLOSED" else "·"
    print(f'    {mark} {n["repository"]["nameWithOwner"]}#{n["number"]} {n["title"][:60]} [{n.get("state")}]')
if not bb.get("nodes"):
    print("    (none)")
PY
  ;;
*) echo "usage: roadmap_dep.sh add|rm <blocked-url> <blocking-url>  |  list <issue-url>"; exit 2 ;;
esac
