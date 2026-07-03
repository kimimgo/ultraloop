#!/usr/bin/env bash
# regen_progress.sh — board (SoT) → PROGRESS.md regeneration (read-only view). Every loop ①.
#   PROGRESS.md is never edited directly — it is redrawn from the board only here.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; PROJ="$(cfg_get roadmap.project_number "")"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
STATE_DIR="$(ue_state_dir)"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
{
  echo "<!-- ⚠️ auto-regenerated file — do not edit directly. regen_progress.sh redraws it from the board (SoT) -->"
  echo "# PROGRESS (read-only view) · $TS"
  echo
  echo "- repo: \`$REPO\`  · board: \`${PROJ:-(not set)}\`"
  HB="$STATE_DIR/heartbeat"; [ -f "$HB" ] && echo "- last heartbeat: $(date -d @"$(cat "$HB")" '+%H:%M:%S' 2>/dev/null || cat "$HB")"
  LC="$STATE_DIR/loop-count"; [ -f "$LC" ] && echo "- loops: $(cat "$LC")"
  echo
  # ★ north star re-reading (north-star.md §4) — structurally re-injects the ultimate goal into every loop context.
  #   Source = the north-star labeled issue (SoT). If absent, config.mission fallback (state the absence explicitly — no silent degrade).
  echo "## ⭐ North Star (ultimate goal — reread every loop)"
  NS=""
  command -v gh >/dev/null 2>&1 && NS="$(gh issue list -R "$REPO" --label north-star --state all --limit 1 \
      --json number,title,body -q '.[0] | "**\(.title)** (#\(.number))\n\n\(.body)"' 2>/dev/null)"
  if [ -n "$NS" ]; then printf '%s\n' "$NS" | head -20
  else
    M="$(cfg_get mission "")"
    if [ -n "$M" ]; then echo "_(no north-star issue — config.mission fallback. Must be finalized in pm)_"; printf '%s\n' "$M" | head -6
    else echo "- (undefined — pm planning needed: references/north-star.md §1)"; fi
  fi
  echo
  echo "## 🎯 Milestone goals (with verdict questions — north-star.md §2)"
  command -v gh >/dev/null 2>&1 && gh api "repos/$REPO/milestones?state=open&per_page=20" \
      -q '.[] | "- **\(.title)** (\(.closed_issues)/\(.closed_issues+.open_issues)): \(.description // "⚠ no goal statement")"' 2>/dev/null \
    | head -20 || echo "- (no milestones)"
  echo
  echo "## Board status summary"
  if [ -n "$PROJ" ] && command -v gh >/dev/null 2>&1; then
    GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh project item-list "$PROJ" --owner "${REPO%%/*}" --format json 2>/dev/null \
      | python3 -c 'import json,sys,collections
try:
 d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
 c=collections.Counter(str(it.get("status","?")) for it in items)
 for k,v in sorted(c.items()): print(f"- {k}: {v}")
 print(f"- total: {len(items)}")
except Exception as e: print(f"- (board query failed: {e})")' 2>/dev/null || echo "- (board query failed)"
  else
    echo "- (board not configured — roadmap_sync needed)"
  fi
  echo
  echo "## Approval queue pending"
  AQ="$STATE_DIR/../ultraloop-approvals"; [ -d "$AQ" ] && ls "$AQ"/*.pending 2>/dev/null | sed 's#.*/#- #' || echo "- (none)"
  echo
  echo "## Blockers (blocked issues)"
  command -v gh >/dev/null 2>&1 && gh issue list -R "$REPO" --label blocked --state open --json number,title -q '.[]|"- #\(.number) \(.title)"' 2>/dev/null || true
} > PROGRESS.md 2>/dev/null || { ue_log "PROGRESS.md write failed — cwd may be unwritable; run from the repo root"; exit 1; }
ue_log "PROGRESS.md regenerated"
