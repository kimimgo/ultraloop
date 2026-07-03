#!/usr/bin/env bash
# roadmap_item.sh — create a roadmap item (=issue) + board add + Horizon/Date setting + sub-issue hierarchy + milestone.
#   3-tier: Long-term (Initiative) ⊃ Mid-term (Epic) ⊃ Short-term (Task). Hierarchy via native sub-issues (addSubIssue).
# usage:
#   roadmap_item.sh <owner/repo> <horizon> "<title>" \
#       [--parent <parent-issue-url>] [--milestone "<name>"] [--date YYYY-MM-DD] \
#       [--body "<body>"] [--label <label>] [--status <option-name>]
#   roadmap_item.sh horizons        # list the configured horizons
# exit 0=ok · 2=argument error · 3=board not set · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"

HORIZONS="$(cfg_get horizons '["Long-term","Mid-term","Short-term"]')"
if [ "${1:-}" = "horizons" ]; then printf '%s\n' "$HORIZONS" | python3 -c 'import json,sys;print(" / ".join(json.load(sys.stdin)))'; exit 0; fi

REPO="${1:?usage: roadmap_item.sh <owner/repo> <horizon> \"<title>\" [opts]}"
HORIZON="${2:?horizon required (e.g. Long-term/Mid-term/Short-term)}"
TITLE="${3:?title required}"; shift 3 || true
PARENT=""; MILESTONE=""; DATE=""; BODY=""; LABEL=""; STATUS=""
while [ $# -gt 0 ]; do case "$1" in
  --parent) PARENT="$2"; shift 2;; --milestone) MILESTONE="$2"; shift 2;;
  --date) DATE="$2"; shift 2;; --body) BODY="$2"; shift 2;;
  --label) LABEL="$2"; shift 2;; --status) STATUS="$2"; shift 2;;
  *) ghr_log "unknown option: $1 — see the usage in the script header"; exit 2;; esac; done

# validate horizon (typo guard)
echo "$HORIZONS" | python3 -c 'import json,sys; sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' "$HORIZON" \
  || { ghr_log "horizon not defined: $HORIZON — available: $(printf '%s' "$HORIZONS" | python3 -c 'import json,sys;print(", ".join(json.load(sys.stdin)))')"; exit 2; }

PNODE="$(cfg_get board.project_node_id "")"
[ -n "$PNODE" ] || { ghr_log "board.project_node_id not set — run roadmap_bootstrap.sh first (and keep gh-roadmap.config.yaml at the working repo root)"; exit 3; }

# ── 1. create issue ───────────────────────────────────────────────────────────
CREATE_ARGS=(-R "$REPO" --title "$TITLE" --body "${BODY:-_(gh-roadmap: $HORIZON)_}")
[ -n "$LABEL" ] && CREATE_ARGS+=(--label "$LABEL")
URL="$(gh issue create "${CREATE_ARGS[@]}" 2>/tmp/ghr_iss.err)" \
  || { ghr_log "issue creation failed: $(tail -1 /tmp/ghr_iss.err) — check repo access and that the label exists"; exit 5; }
echo "ISSUE $URL"

# ── 2. milestone (repo scope) — ensure-then-assign ──────────────────────────
if [ -n "$MILESTONE" ]; then
  MNUM="$(gh api "repos/$REPO/milestones?state=all" --jq ".[] | select(.title==\"$MILESTONE\") | .number" 2>/dev/null | head -1)"
  [ -z "$MNUM" ] && MNUM="$(gh api "repos/$REPO/milestones" -f title="$MILESTONE" --jq .number 2>/dev/null)"
  if [ -n "$MNUM" ]; then gh issue edit "$URL" --milestone "$MILESTONE" >/dev/null 2>&1 && echo "  ✓ milestone=$MILESTONE (#$MNUM)" || echo "  ✗ milestone assignment failed (probable cause: issue permissions) — assign it manually with gh issue edit"; \
  else echo "  ✗ milestone ensure failed: $MILESTONE (probable cause: no push access to $REPO) — create the milestone manually or fix token scopes"; fi
fi

# ── 3. board add + Horizon/Date/Status fields ───────────────────────────────
CNODE="$(ghr_issue_node "$URL")"; [ -n "$CNODE" ] || { ghr_log "issue node resolution failed (probable cause: token lacks repo scope) — check the printed ISSUE url and the token"; exit 5; }
ITEM="$(ghr_add_item "$PNODE" "$CNODE")"; [ -n "$ITEM" ] || { ghr_log "board add failed (probable cause: stale board.project_node_id or token lacks project scope) — re-run roadmap_bootstrap.sh"; exit 5; }
echo "  ✓ board item=$ITEM"
ghr_set_field "$PNODE" "$ITEM" "Horizon" "$HORIZON" && echo "  ✓ Horizon=$HORIZON" || echo "  ✗ Horizon set failed (field missing? check bootstrap)"
[ -n "$DATE" ]   && { ghr_set_field "$PNODE" "$ITEM" "Target Date" "$DATE" && echo "  ✓ Target Date=$DATE" || echo "  ✗ Target Date set failed — check the YYYY-MM-DD format and that the field exists"; }
[ -n "$STATUS" ] && { ghr_set_field "$PNODE" "$ITEM" "Status" "$STATUS" && echo "  ✓ Status=$STATUS" || echo "  ✗ Status set failed — check that the option exists in the Status field"; }

# ── 4. hierarchy — link as a sub-issue of the parent item (native) ──────────
if [ -n "$PARENT" ]; then
  PNODE_ISS="$(ghr_issue_node "$PARENT")"; [ -n "$PNODE_ISS" ] || { ghr_log "parent issue node resolution failed: $PARENT — check the URL and the token repo scope"; exit 5; }
  gq -f query='mutation($i:ID!,$s:ID!){ addSubIssue(input:{issueId:$i,subIssueId:$s}){ subIssue{ number } } }' \
     -f i="$PNODE_ISS" -f s="$CNODE" >/dev/null 2>&1 \
    && echo "  ✓ sub-issue ← $PARENT" || echo "  ✗ sub-issue link failed: $(head -1 /tmp/ghr_gq.err) — check the token repo scope"
fi
echo "DONE $URL"
