#!/usr/bin/env bash
# goal_check.sh — evaluate DoD (= goal condition) fulfillment for the *machine-verifiable part*.
#   exit 0  = met (stop allowed)
#   exit 1  = not met — one line of "remaining reason" on stdout (the gate uses it as reason)
#
# Non-determinism principle: only *machine-checkable signals* are inspected here (board counts, CI, evidence files, HITL markers).
# Subtle quality judgments are made by the agent in the loop. When a signal is ambiguous, judge conservatively as **not met (1)**.
#
# If config.engine.goal.condition is "DoD" (default), run the checks below. If it is a free-form string, the agent interprets its intent.

set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

REPO="$(ue_repo)"
COND="$(cfg_get engine.goal.condition DoD)"
fail() { echo "$1"; exit 1; }

# Free-form condition cannot be auto-judged → hand off to agent judgment (conservatively not met, but state the reason)
if [ "$COND" != "DoD" ]; then
  fail "condition=$COND — the agent must judge fulfillment directly (not machine-verifiable)"
fi
[ -n "$REPO" ] || fail "repo not resolved — check config.repo or gh auth"

# 1-scope) v0.10 run scope: engine.goal.scope=milestone:<title> narrows THIS RUN to one
#   milestone — the machine counterpart of north-star.md §2 (per-run milestone goals).
#   Provider-agnostic: the loop closes an issue when its card reaches Done, so open issues
#   in the milestone == remaining scoped work. Default scope=board keeps full-board
#   semantics below untouched. The north-star reference issue is never counted.
MS="$(ue_goal_scope 2>/dev/null || true)"
if [ -n "$MS" ]; then
  command -v gh >/dev/null 2>&1 || fail "milestone scope set but gh unavailable — conservatively not met"
  OPEN="$(gh issue list -R "$REPO" --milestone "$MS" --state open --limit 1000 --json number,labels \
        -q '[.[] | select((.labels | map(.name) | index("north-star")) | not)] | length' 2>/dev/null)"
  case "$OPEN" in
    0) : ;;
    "") fail "milestone scope query failed (milestone \"$MS\" missing? transient?) — conservatively not met" ;;
    *) fail "milestone \"$MS\": ${OPEN} open issues remaining" ;;
  esac
  BLK="$(gh issue list -R "$REPO" --milestone "$MS" --label blocked --state open --json number -q 'length' 2>/dev/null || echo 0)"
  [ "${BLK:-0}" -gt 0 ] 2>/dev/null && fail "milestone \"$MS\": ${BLK} open blocked issues"
fi

# 1) Board (scope=board only): not met while non-Done cards remain.
#    (Requires a project-scope token. On query failure, conservatively not met.)
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
PROJ="$(cfg_get roadmap.project_number "")"
if [ -z "$MS" ] && [ -n "$PROJ" ] && command -v gh >/dev/null 2>&1; then
  OWNER="${REPO%%/*}"
  # gh project needs ≥2.31 — if an old apt version (2.4.0) shadows it at the front of PATH, fall back to ~/.local/bin/gh
  # (same version-independence as roadmap_sync.sh — if absent, falls through to conservative not-met as before)
  GHP="gh"
  if ! gh project --help >/dev/null 2>&1 && [ -x "$HOME/.local/bin/gh" ]; then GHP="$HOME/.local/bin/gh"; fi
  # On a shared board (board.shared=true — one board spanning N repos) evaluate only THIS repo's cards.
  # ultraloop is single-repo: its DoD = "this repo's assigned slice Done", never the whole shared board.
  REPO_FILTER=""
  [ "$(cfg_get board.shared false)" = "true" ] && REPO_FILTER="$REPO"
  # Count of non-Done cards — empty on failure
  OPEN="$( { GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" "$GHP" project item-list "$PROJ" --owner "$OWNER" --format json 2>/dev/null \
            | UE_REPO_FILTER="$REPO_FILTER" python3 -c 'import json,os,sys
try:
  d=json.load(sys.stdin); items=d.get("items",d if isinstance(d,list) else [])
  repo=os.environ.get("UE_REPO_FILTER","").strip().lower()
  def mine(it):
    if not repo: return True
    cand=str(it.get("repository") or (it.get("content") or {}).get("repository") or "").lower().rstrip("/")
    return cand.endswith("/"+repo) or cand==repo
  n=sum(1 for it in items if mine(it) and str(it.get("status","")).lower() not in ("done","closed"))
  print(n)
except Exception: print("ERR")' ; } 2>/dev/null )"
  case "$OPEN" in
    0) : ;;                                   # all cards Done → pass
    ERR|"") fail "board query failed (possibly transient) — conservatively not met" ;;
    *) fail "board has ${OPEN} non-Done cards remaining" ;;
  esac
elif [ -z "$MS" ] && [ "$(cfg_get roadmap.provider github_projects_v2)" = "milestones" ] && command -v gh >/dev/null 2>&1; then
  # Fallback (R2, roadmap-model §6): Projects v2 unavailable → issue-based (issues = work cards).
  #   Equivalent of the board "non-Done card count" = number of open issues. 0 means pass.
  #   The north-star issue is a reference point, not work (north-star.md §5) — not counted even while open.
  OPEN="$(gh issue list -R "$REPO" --state open --limit 1000 --json number,labels \
        -q '[.[] | select((.labels | map(.name) | index("north-star")) | not)] | length' 2>/dev/null)"
  case "$OPEN" in
    0) : ;;                                   # all issues closed → pass
    "") fail "issue query failed (possibly transient) — conservatively not met" ;;
    *) fail "${OPEN} open issues remaining (board fallback: all issues must be closed)" ;;
  esac
elif [ -z "$MS" ]; then
  fail "board/milestones not configured — roadmap sync needed (check roadmap.provider)"
fi

# 2) Not met while open blocked issues exist (board scope; milestone scope checked its own above).
if [ -z "$MS" ] && command -v gh >/dev/null 2>&1; then
  BLK="$(gh issue list -R "$REPO" --label blocked --state open --json number -q 'length' 2>/dev/null || echo 0)"
  [ "${BLK:-0}" -gt 0 ] 2>/dev/null && fail "${BLK} open blocked issues"
fi

# 3) E2E evidence: verify reports exist + content (final-result marker). Count alone cannot filter empty/placeholder/stale ones.
if [ -d "./e2e/reports" ]; then
  CNT="$(find ./e2e/reports -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  [ "${CNT:-0}" -ge 1 ] || fail "no E2E evidence reports (e2e/reports/*.md)"
  # Not met while an unresolved FAIL marker (**FAIL** in report.template "## Final result") remains.
  if grep -rlE '\*\*FAIL\*\*' ./e2e/reports/*.md >/dev/null 2>&1; then fail "unresolved **FAIL** marker in E2E reports"; fi
  # At least one report must carry a **PASS** marker (placeholders alone are not met — a PASS/FAIL guidance note is not a marker).
  grep -rlE '\*\*PASS\*\*' ./e2e/reports/*.md >/dev/null 2>&1 || fail "no **PASS** marker in E2E reports (not written or not passed)"
else
  fail "e2e/reports directory missing — Tier2 E2E not performed"
fi

# 4) Production HITL approval marker — scripts/mark_deployed.sh writes it after deploy success + health OK (only creation path).
HITL="$(cfg_get hitl.enabled true)"
if [ "$HITL" = "true" ]; then
  DM="./.ultraloop/prod-deployed"
  [ -n "$MS" ] && DM="./.ultraloop/prod-deployed-$(ue_scope_slug "$MS")"   # per-milestone deploy evidence: a previous milestone deploy must not satisfy this run
  [ -f "$DM" ] || fail "production HITL deploy incomplete (${DM#./} marker missing)"
fi

# All machine checks passed → met
exit 0
