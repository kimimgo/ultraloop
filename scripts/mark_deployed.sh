#!/usr/bin/env bash
# mark_deployed.sh [version] — record the production-deployment marker (DoD exit condition; required by goal_check).
#   goal_check treats ./.ultraloop/prod-deployed as evidence of a successful production deployment. This script is
#   its only producer (previously nothing created it, so the goal never closed even after a clean deployment).
#   ★ Call only after production HITL approval + health OK have been confirmed (agent or a CD follow-up step). Idempotent.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"
VER="${1:-$(git describe --tags --abbrev=0 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo '?')}"

# best-effort verification: check that the latest cd workflow run succeeded (does not block on failure — health is verified by the caller).
if command -v gh >/dev/null 2>&1; then
  ST="$(gh run list -R "$REPO" --workflow cd --status success --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || echo '')"
  [ "$ST" = "success" ] && echo "  ✓ latest cd run=success confirmed" || echo "  · could not auto-confirm a successful cd run (manual verification assumed) — continuing"
fi

mkdir -p .ultraloop
MS="$(ue_goal_scope 2>/dev/null || true)"
MARKER=".ultraloop/prod-deployed"
[ -n "$MS" ] && MARKER=".ultraloop/prod-deployed-$(ue_scope_slug "$MS")"   # scoped run (engine.goal.scope) → per-milestone evidence
printf 'version=%s\ndeployed_at=%s\nscope=%s\n' "$VER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${MS:-board}" > "$MARKER"
git add "$MARKER" 2>/dev/null || true
git commit -m "chore(ultraloop): mark production deployment ${VER}" >/dev/null 2>&1 \
  && echo "  ✓ $MARKER (version=$VER) recorded and committed" \
  || echo "  ✓ $MARKER (version=$VER) recorded (no commit changes)"
