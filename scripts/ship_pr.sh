#!/usr/bin/env bash
# ship_pr.sh ["title"] — push → ★methodology gate → PR → CI watch → ★pre-merge E2E → squash merge on pass.
#   exit 0 = merged · 1 = CI failed · 6 = E2E failed (no merge) · 7 = methodology gate failed (no merge)
# ★ E2E is the pre-merge gate. Green CI alone does not merge.
# ★ methodology_check.sh is the deterministic TDD-evidence gate (v0.16): test:* before feat:/fix:* on
#   the branch. It self-degrades via config (methodology.tdd_evidence warn|off → exit 0), so legacy
#   repos are never silently blocked; enforce mode blocks a merge that skipped test-first work.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
TITLE="${1:-$(git log -1 --pretty=%s 2>/dev/null)}"

git push -u origin "$BR" 2>/dev/null || { ue_log "push failed — check remote access and branch protection, then retry"; exit 1; }
gh pr view "$BR" >/dev/null 2>&1 || gh pr create -R "$REPO" --base "$DEFB" --head "$BR" --title "$TITLE" --fill 2>/dev/null || true

# ★ methodology evidence gate (pre-merge) — the branch must prove test-first work (v0.16, #6).
# Self-degrades via config (warn|off → exit 0); enforce mode blocks the merge on a commit-order violation.
echo "→ methodology evidence gate…"
if ! bash "$SDIR/methodology_check.sh" "$BR"; then
  ue_log "methodology evidence gate failed → not merging (test-first commit order — see methodology_check output above)"; exit 7
fi

# CI watch
echo "→ CI watch…"
if ! gh pr checks "$BR" --watch --interval 20 2>/dev/null; then
  ue_log "CI failed → fix and retry on the same branch (no bypassing protections)"; exit 1
fi

# ★ pre-merge E2E (gate). Scenario arguments are decided by the agent to fit the environment/issue.
ISSUE="$(printf '%s' "$BR" | grep -oE '[0-9]+' | head -1)"
echo "→ pre-merge E2E (issue ${ISSUE:-?})…"
if [ -x "$SDIR/e2e_up.sh" ]; then
  bash "$SDIR/e2e_up.sh" "${ISSUE:-0}" || { ue_log "E2E up failed — environment did not start; check e2e_up output"; bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null; exit 6; }
  if ! bash "$SDIR/e2e_run.sh" "${ISSUE:-0}"; then
    ue_log "E2E deterministic failure → not merging. Apply e2e:fail + file a bug issue."
    bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null || true
    exit 6
  fi
  bash "$SDIR/e2e_down.sh" "${ISSUE:-0}" 2>/dev/null || true
else
  ue_log "e2e_up.sh missing — E2E gate not executed; check the scripts directory and config"; exit 6
fi

# passed → squash merge (the agent adds an evidence trailer with the e2e report path)
gh pr merge "$BR" --squash --auto --delete-branch 2>/dev/null && { ue_log "merge complete"; exit 0; }
ue_log "merge failed (conflict/permissions) — resolve serialization and retry"; exit 1
