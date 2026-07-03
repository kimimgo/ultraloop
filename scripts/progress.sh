#!/usr/bin/env bash
# progress.sh — progress, E2E, DoD, and traceability summary (at a glance for humans/agents). Read-only.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"
STATE_DIR="$(ue_state_dir)"

echo "== ultraloop progress · $REPO =="
[ -f "$STATE_DIR/loop-count" ] && echo "loops: $(cat "$STATE_DIR/loop-count")"
[ -f "$STATE_DIR/run-start" ] && echo "elapsed: $(( ( $(date +%s) - $(cat "$STATE_DIR/run-start") ) / 60 )) min"

if command -v gh >/dev/null 2>&1; then
  echo "-- issues --"
  echo "open:   $(gh issue list -R "$REPO" --state open --json number -q length 2>/dev/null || echo '?')"
  echo "blocked:$(gh issue list -R "$REPO" --label blocked --state open --json number -q length 2>/dev/null || echo '?')"
  echo "-- PR --"
  echo "open PR:$(gh pr list -R "$REPO" --state open --json number -q length 2>/dev/null || echo '?')"
fi
echo "-- E2E evidence --"
[ -d ./e2e/reports ] && echo "reports: $(find ./e2e/reports -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" || echo "reports: 0"
echo "-- goal gate state --"
ST="$STATE_DIR/goal-$(printf '%s' "$(pwd)" | cksum | cut -d' ' -f1).state"
[ -f "$ST" ] && cat "$ST" || echo "(no evaluation yet)"
echo
echo "DoD details: references/definition-of-done.md · goal verdict: goal_check.sh"
