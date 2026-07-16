#!/usr/bin/env bash
# worktree_gate.sh — forced HITL confirmation before draining from a linked worktree (#4, owner decision).
#
# Rule: in a LINKED git worktree, /ultraloop:loop must NEVER start draining silently — regardless of
# goal.enabled / autonomy. The human must explicitly confirm "this worktree, this scope, drain NOW".
# The main worktree is untouched (no prompt — current behavior).
#
# Deterministic split: this script DETECTS and RECORDS; the agent PROMPTS.
#   check    main worktree → exit 0 (no gate).
#            linked worktree + valid confirm token → exit 0.
#            linked worktree, no/stale token → print the confirmation context block
#            (resolved scope · board · sibling-worktree warning · lease holder) → exit 4.
#   confirm  write the confirm token. ONLY call after an explicit human YES
#            (AskUserQuestion, or an approval-queue Y in unattended runs). Never call it on your own.
#   revoke   drop the token (forces re-confirmation).
# Token validity: per RUN and per SCOPE — it dies when a new run starts (run-start newer / cost_guard
# --reset) or when the resolved scope changed since confirmation. Non-interactive invocation with no
# token = DEFAULT DENY: the agent must park (approval queue + notify) and end the tick without cards.
# exit: 0 = drain may proceed · 4 = human confirmation required first · 2 = usage
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || { echo "lib missing" >&2; exit 4; }

STATE_DIR="$(ue_state_dir)"
TOKEN="$STATE_DIR/worktree-drain-confirm"
RUN_START="$STATE_DIR/run-start"

# conservative: if git itself cannot answer, treat as gated (never silently drain on ambiguity)
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository — cannot judge worktree; confirmation required"; exit 4; }

resolved_scope() {  # effective run scope (board-first, _lib.sh) — mismatch shows as such, loudly
  local s rc; s="$(ue_active_milestone 2>/dev/null)"; rc=$?
  [ "$rc" -eq 4 ] && { printf 'SCOPE MISMATCH (board="%s" ≠ config)' "$s"; return; }
  printf '%s' "${s:-board (full board)}"
}

token_valid() {
  [ -f "$TOKEN" ] || return 1
  # the token authorizes exactly ONE run: no active run clock (post-reset/completion) = stale token,
  # and a run-start written AFTER the token (a newer run) also invalidates it. `confirm` starts the
  # run clock itself, so within the confirmed run the token always predates-or-equals run-start.
  [ -f "$RUN_START" ] || return 1
  [ "$RUN_START" -nt "$TOKEN" ] && return 1
  # a retargeted scope invalidates the token (confirmed scope ≠ current scope)
  local rec cur
  rec="$(grep -E '^SCOPE=' "$TOKEN" 2>/dev/null | tail -1 | cut -d= -f2-)"
  cur="$(resolved_scope)"
  [ "$rec" = "$cur" ]
}

siblings() {  # other worktrees of this clone that carry an ultraloop config (= potential drainers)
  local self p cfgline
  self="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  git worktree list --porcelain 2>/dev/null | sed -nE 's/^worktree //p' | while IFS= read -r p; do
    [ "$p" = "$self" ] && continue
    if [ -f "$p/ultraloop.config.yaml" ]; then
      cfgline="$(grep -E '^\s*scope:' "$p/ultraloop.config.yaml" 2>/dev/null | head -1 | sed -E 's/^\s*//; s/\s*#.*$//')"
      printf '  - %s  (%s)\n' "$p" "${cfgline:-scope: unset}"
    fi
  done
}

case "${1:-check}" in
  check)
    if ! ue_is_linked_worktree; then echo "main worktree — no gate"; exit 0; fi
    if token_valid; then echo "linked worktree — drain confirmed for this run/scope"; exit 0; fi
    cat <<EOF
LINKED WORKTREE — human confirmation REQUIRED before any card is picked (forced, config-independent).
  worktree : $(git rev-parse --show-toplevel 2>/dev/null || pwd)
  repo     : $(ue_repo)
  board    : project #$(cfg_get roadmap.project_number "?") ($(cfg_get roadmap.project_node_id "?"))
  scope    : $(resolved_scope)
  lease    : $(bash "$SDIR/drain_lease.sh" status 2>/dev/null || echo "unknown")
  sibling worktrees sharing this repo/board (concurrent drain = card race):
$(siblings)
Ask the human: "start draining from THIS worktree, with THIS scope, NOW?" — on an explicit YES run
\`worktree_gate.sh confirm\`; unattended (no human reachable) = DENY + approval queue + notify.
EOF
    exit 4 ;;
  confirm)
    if ! ue_is_linked_worktree; then echo "main worktree — nothing to confirm"; exit 0; fi
    # start the run clock first so the token belongs to THIS run (token mtime >= run-start mtime)
    [ -f "$RUN_START" ] || date +%s > "$RUN_START" 2>/dev/null || true
    { echo "WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      echo "SCOPE=$(resolved_scope)"
      echo "CONFIRMED=$(date +%s)"
    } > "$TOKEN" 2>/dev/null || { echo "cannot write confirm token ($TOKEN)"; exit 4; }
    echo "worktree drain confirmed (token: $TOKEN)"; exit 0 ;;
  revoke)
    rm -f "$TOKEN" 2>/dev/null || true; echo "confirm token revoked"; exit 0 ;;
  *) echo "usage: worktree_gate.sh [check|confirm|revoke]" >&2; exit 2 ;;
esac
