#!/usr/bin/env bash
# config_check.sh — v0.13 "config doctor" for an ultraloop project.
#   Loud, never silent-proceed (mirrors bootstrap_repo.sh §0 probe): prints ✓/✗/· per check.
#   exit 0 = every REQUIRED item ok; exit 1 with a one-line reason when a REQUIRED item is
#   missing; optional items warn only (·). Safe to call advisory from SessionStart.
#   REQUIRED: config present · project-scope capability (env PAT or gh keyring scope) · repo resolved · gh auth ·
#             bootstrap marker · gh-roadmap sub-skill.
#   OPTIONAL: self-hosted runner (best-effort) · superpowers · vendored pm skills.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SDIR/.." && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

FAIL=""                                    # first REQUIRED failure reason (the one-line verdict)
req_fail() { [ -n "$FAIL" ] || FAIL="$1"; }

echo "== ultraloop config doctor =="

# ── 1. config present (gateway — nothing else is meaningful without it) ───────────
CFG="$(ue_config_path)"
if [ ! -f "$CFG" ]; then
  echo "  ✗ config: ultraloop.config.yaml not found ($CFG) — run bootstrap_repo.sh or cp config.example.yaml"
  echo "config-doctor: FAIL — ultraloop.config.yaml missing"
  exit 1
fi
echo "  ✓ config: $CFG"
PROJ="$(cd "$(dirname "$CFG")" && pwd)"

# ── 2. project-scope token (REQUIRED — Projects v2 automation needs the `project` SCOPE) ──
#   Capability check, not mechanism: an env PAT *or* the gh keyring token carrying the 'project'
#   scope both work. Runtime calls pass GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" through, and gh
#   treats an EMPTY GH_TOKEN as unset → falls back to its own keyring auth (verified). The old
#   env-presence check FAILed hosts whose gh already had the scope — a recurring false alarm.
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
if [ -n "${!TOKEN_ENV:-${GH_TOKEN:-}}" ]; then
  echo "  ✓ project-scope token (env $TOKEN_ENV)"
elif gh auth status 2>&1 | grep -q "'project'"; then
  echo "  ✓ project-scope token (gh keyring token carries the 'project' scope — no env var needed)"
else
  echo "  ✗ project-scope token: no env $TOKEN_ENV/GH_TOKEN and gh's own token lacks the 'project' scope"
  echo "    → either: gh auth refresh -h github.com -s project     (add the scope to gh's keyring token)"
  echo "    → or:     export $TOKEN_ENV=<PAT with project scope>   (CI/unattended env injection)"
  req_fail "project-scope capability missing (gh auth refresh -s project, or set $TOKEN_ENV)"
fi

# ── 3. repo resolved (REQUIRED) ──────────────────────────────────────────────────
REPO="$(ue_repo)"
if [ -n "$REPO" ]; then
  echo "  ✓ repo: $REPO"
else
  echo "  ✗ repo: unresolved — set config.repo or pass owner/name (/ultraloop owner/name)"
  req_fail "repo unresolved (set config.repo)"
fi

# ── 4. gh auth (REQUIRED) ────────────────────────────────────────────────────────
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "  ✓ gh auth"
else
  echo "  ✗ gh auth: not logged in — run gh auth login"
  req_fail "gh not authenticated (gh auth login)"
fi

# ── 5. bootstrap marker (REQUIRED — proves bootstrap_repo.sh completed its prerequisites) ──
if [ -f "$PROJ/.claude/.ultraloop-bootstrapped" ]; then
  echo "  ✓ bootstrap marker (.claude/.ultraloop-bootstrapped)"
else
  echo "  ✗ bootstrap marker (.claude/.ultraloop-bootstrapped) absent — run bootstrap_repo.sh"
  req_fail "bootstrap marker absent (run bootstrap_repo.sh)"
fi

# ── 6. gh-roadmap sub-skill (REQUIRED — sole board authority; bundled since v0.8.0) ──
#   Priority: local user copy → bundled skills/ → plugin bundle/cache (matches bootstrap §0.1).
GHR_DIR=""
for d in "$HOME/.claude/skills/gh-roadmap" "$SKILL_DIR/skills/gh-roadmap" \
         "$HOME"/.claude/plugins/*/skills/gh-roadmap "$HOME"/.claude/plugins/cache/*/*/skills/gh-roadmap; do
  [ -f "$d/SKILL.md" ] && { GHR_DIR="$d"; break; }
done
if [ -n "$GHR_DIR" ]; then
  echo "  ✓ gh-roadmap sub-skill: $GHR_DIR"
else
  echo "  ✗ gh-roadmap sub-skill missing (bundle damaged?) — board structure/setup unavailable"
  req_fail "gh-roadmap sub-skill missing"
fi

# superpowers — REQUIRED barrier (v0.16 #6): the loop's per-lane build methodology. Absent → FAIL
# unless methodology.superpowers=optional (legacy loud-fallback). ue_superpowers_dir fixes the old
# probe that missed the real plugins/cache/*/superpowers/* layout.
SP_REQ="$(cfg_get methodology.superpowers required)"
SP_DIR="$(ue_superpowers_dir || true)"
if [ -n "$SP_DIR" ]; then
  SP_N="$(ls "$SP_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')"
  echo "  ✓ superpowers methodology: $SP_DIR ($SP_N skills)"
elif [ "$SP_REQ" = "optional" ]; then
  echo "  · superpowers: not installed — methodology barrier DISABLED by config (legacy loud-fallback; not recommended)"
else
  echo "  ✗ superpowers plugin missing — the loop's build methodology is a REQUIRED barrier"
  echo "     remedy: claude plugin install superpowers@claude-plugins-official  (or set ULTRALOOP_SUPERPOWERS_DIR=<dir>)"
  echo "     or set methodology.superpowers: optional in ultraloop.config.yaml (legacy fallback — not recommended)"
  req_fail "superpowers missing (methodology barrier — install it, or set methodology.superpowers: optional)"
fi

# ── optional (warnings only — never block exit) ──────────────────────────────────
# self-hosted runner — best-effort; a permission/offline failure must not hard-fail (agent re-verifies in loop ①).
RUN="$(gh api "repos/$REPO/actions/runners" --jq '[.runners[]|select(.status=="online")]|length' 2>/dev/null || echo "?")"
case "$RUN" in
  "?") echo "  · self-hosted runner: query failed (permission/offline) — re-verify before waiting on CI" ;;
  0)   echo "  · self-hosted runner: none online — CI (runs-on: self-hosted) will queue until one registers" ;;
  *)   echo "  ✓ self-hosted runner online: $RUN" ;;
esac

# native worktree provider (advisory only — never fails). orca+worktrees is the baseline environment
# (worktree-strategy.md §6), NOT a runtime dependency: no script requires it, so CI/bats stay green without it.
if command -v orca-ide >/dev/null 2>&1; then
  echo "  ✓ native worktree provider: orca-ide (worktree-strategy.md §6)"
elif command -v ows >/dev/null 2>&1; then
  echo "  ✓ native worktree provider: ows (worktree-strategy.md §6)"
else
  echo "  · native worktree provider: none — raw git worktrees only (orca/ows recommended; worktree-strategy.md §6)"
fi

# vendored pm skills (optional — one availability summary line).
PM_HAVE=0; PM_TOTAL=0
for s in brainstorming identify-assumptions opportunity-solution-tree pre-mortem prioritize-assumptions; do
  PM_TOTAL=$((PM_TOTAL + 1))
  { [ -f "$SKILL_DIR/skills/$s/SKILL.md" ] || [ -d "$HOME/.claude/skills/$s" ]; } && PM_HAVE=$((PM_HAVE + 1))
done
echo "  · vendored pm skills: $PM_HAVE/$PM_TOTAL bundled (optional — loop falls back if any absent)"

# ── verdict (one-line summary; the SessionStart advisory greps the last line) ─────
if [ -n "$FAIL" ]; then
  echo "config-doctor: FAIL — $FAIL"
  exit 1
fi
echo "config-doctor: OK — all required checks passed (runner=$RUN)"
