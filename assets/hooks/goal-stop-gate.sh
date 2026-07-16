#!/usr/bin/env bash
# goal-stop-gate.sh — reproduction of the /goal stop-blocking gate (Stop hook).
#
# Behavior (1:1 with the built-in /goal): every time the agent tries to stop, re-check whether the DoD is met.
#   - met     → allow stop (goal clear).
#   - not met → block stop + accumulate iteration/last_reason + continue.
#
# ★ Safety (mandatory, cannot be turned off): unguarded Stop-hook re-injection runs away (past incident). So *always* FAIL-OPEN.
#   On anything suspicious — errors, caps, locks — unconditionally **allow stop** (never trap a human in the loop).
#   *Blocking* a stop happens only when all 4 align: (1) lock passed (2) budget passed (3) iteration under cap (4) goal not met.
#
# Install (v0.13.4): ships with the PLUGIN's own hook registration — hooks/hooks.json registers this script via
#   ${CLAUDE_PLUGIN_ROOT} (version-independent, auto-follows plugin updates). No per-repo settings.json injection:
#   the old bootstrap injection wrote a version-pinned cache path that broke on every update and accumulated
#   duplicates (issue #1); bootstrap now only CLEANS UP those legacy entries.
# Because the hook is global, the gate must self-guard: outside an ultraloop project (no ultraloop.config.yaml
#   found walking up from cwd) it allows immediately — see the guard right below the lib source.
# Invocation: `bash ${CLAUDE_PLUGIN_ROOT}/assets/hooks/goal-stop-gate.sh` (cwd=session cwd, stdin=hook payload).
# Output: on block, {"decision":"block","reason":"..."} on stdout · on allow, exit 0 (no output).

set -uo pipefail
exec 9<&0 || true   # stdin (hook payload) — currently only stop_hook_active is consulted

# --- own location → skill root → _lib.sh ------------------------------------
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
# shellcheck source=/dev/null
. "$SKILL_DIR/scripts/_lib.sh" 2>/dev/null || { exit 0; }   # no lib → allow stop

allow() { exit 0; }                                  # allow stop (no output)
block() { printf '{"decision":"block","reason":%s}\n' "$(_json "$1")"; exit 0; }
_json() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || printf '"%s"' "$(printf '%s' "$1" | tr -d '"\n')"; }

# --- self-guard: not an ultraloop project → no gate ---------------------------
# The hook is registered plugin-globally, so it fires on every session stop. Without a config file the
# cfg_get defaults would make goal_check "not met" and BLOCK stops in arbitrary projects — so the very
# first check is config presence. ⚠️ ue_config_path never returns empty (it falls back to
# ./ultraloop.config.yaml even when absent), so the guard must test that the FILE actually exists.
UE_CFG="$(ue_config_path 2>/dev/null)"
[ -n "$UE_CFG" ] && [ -f "$UE_CFG" ] || allow

# --- goal disabled → no gate -------------------------------------------------
[ "$(cfg_get engine.goal.enabled true)" = "true" ] || allow

# --- guard 0 (#4): unconfirmed linked worktree → no gate ----------------------
# The gate fires in EVERY session under an ultraloop project — including sibling-worktree sessions
# (ows etc.) doing unrelated work. Blocking their stop with "continue the remaining work (/ultraloop loop)"
# actively RECRUITED them as silent extra drainers (the multi-drainer race, issues #3/#4). So: in a linked
# worktree, gate only a session whose drain was explicitly human-confirmed; otherwise allow the stop.
# The main worktree is untouched (current behavior).
if [ -x "$SKILL_DIR/scripts/worktree_gate.sh" ]; then
  bash "$SKILL_DIR/scripts/worktree_gate.sh" check >/dev/null 2>&1 || allow
fi

STATE_DIR="$(ue_state_dir)"
REPO_KEY="$(printf '%s' "$(pwd)" | cksum | cut -d' ' -f1)"
STATE="$STATE_DIR/goal-$REPO_KEY.state"
# If lock_file in config is empty (""=explicit empty value), cfg_get returns that empty value,
# so the default does not apply → on empty, fall back to a per-uid default path (so the lock guard is not disabled).
LOCK="$(cfg_get engine.goal.lock_file "")"
[ -n "$LOCK" ] || LOCK="$STATE_DIR/ultraloop-goal-$(id -u).lock"

# --- guard 1: lock (re-entry blocking). If locked and fresh, allow stop to avoid a double gate ----
if [ -e "$LOCK" ]; then
  # clean up 10-minute stale locks
  if [ -n "$(find "$LOCK" -mmin +10 2>/dev/null)" ]; then rm -f "$LOCK" 2>/dev/null || true
  else allow; fi
fi
( echo $$ > "$LOCK" ) 2>/dev/null || true
trap 'rm -f "$LOCK" 2>/dev/null || true' EXIT

# --- guard 1.5 (#3): demoted drainer → allow stop -----------------------------
# Only when this seat once held the single-drainer lease (holder file exists) do we spend a network
# round-trip; and only a POSITIVE "held fresh by another drainer" (rc 6) demotes — absent/stale/
# unreachable all keep current behavior (fail-open on ambiguity is the drain side's job, not stop's).
if [ -f "$STATE_DIR/drain-lease.holder" ] && [ -x "$SKILL_DIR/scripts/drain_lease.sh" ]; then
  bash "$SKILL_DIR/scripts/drain_lease.sh" status >/dev/null 2>&1
  if [ "$?" -eq 6 ]; then
    bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop demoted" "drain lease is held by another loop → this session stops draining (stop allowed)" >/dev/null 2>&1 || true
    allow
  fi
fi

# --- guard 2: budget (cost_guard). On budget-stop (exit 7), allow stop -------
if [ -x "$SKILL_DIR/scripts/cost_guard.sh" ]; then
  bash "$SKILL_DIR/scripts/cost_guard.sh" --no-tick >/dev/null 2>&1
  if [ "$?" -eq 7 ]; then
    bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop budget-stop" "budget cap reached → safe stop (incomplete)" >/dev/null 2>&1 || true
    allow
  fi
fi

# --- guard 3: iteration cap ---------------------------------------------------
ITER=0; [ -f "$STATE" ] && ITER="$(grep -E '^ITER=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2)"; ITER="${ITER:-0}"
MAXIT="$(cfg_get engine.goal.max_iterations 200)"; MAXIT="${MAXIT:-200}"
if [ "$ITER" -ge "$MAXIT" ] 2>/dev/null; then
  bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop goal escalation" "iteration cap ($MAXIT) reached → stop allowed (incomplete). Human review needed." >/dev/null 2>&1 || true
  allow
fi

# --- goal-met evaluation (goal_check.sh) --------------------------------------
REASON=""
if [ -x "$SKILL_DIR/scripts/goal_check.sh" ]; then
  REASON="$(bash "$SKILL_DIR/scripts/goal_check.sh" 2>/dev/null)"; RC=$?
else
  RC=0   # no evaluator → treat as met and allow stop (FAIL-OPEN)
fi

if [ "$RC" -eq 0 ]; then
  { echo "ITER=$ITER"; echo "STATUS=met"; echo "LAST_REASON=goal met"; } > "$STATE" 2>/dev/null || true
  # #3: the run is over — give the single-drainer seat back so the next run/worktree can take it.
  if [ -f "$STATE_DIR/drain-lease.holder" ] && [ -x "$SKILL_DIR/scripts/drain_lease.sh" ]; then
    bash "$SKILL_DIR/scripts/drain_lease.sh" release >/dev/null 2>&1 || true
  fi
  allow
fi

# --- not met → iteration++ + (no-progress stall guard) + record reason + block stop -----
ITER=$((ITER+1))
[ -z "$REASON" ] && REASON="DoD not met — check board/CI/E2E/HITL"

# guard 4: no progress (stall). If the goal_check reason is byte-identical to the previous one, observable progress is 0
#   (e.g. all remaining cards are user-parked/blocked, so "N non-Done cards remaining" never shrinks). If the same blocker
#   repeats max_stall_iterations times in a row, allow stop + escalate — cuts busywork and runaway well before
#   the iteration cap (200). (Motivated by the 2026-06-15 incident: at the DoD ceiling all 12 cards were parked, so the gate nagged endlessly →
#   429 errors and context loss. references/failure-modes.md FM1.) On parse failure STALL=0 → previous behavior (fail-safe).
PREV_REASON=""; [ -f "$STATE" ] && PREV_REASON="$(grep -E '^LAST_REASON=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2-)"
STALL=0; [ -f "$STATE" ] && STALL="$(grep -E '^STALL=' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2)"; STALL="${STALL:-0}"; case "$STALL" in ''|*[!0-9]*) STALL=0;; esac
if [ "$REASON" = "$PREV_REASON" ]; then STALL=$((STALL+1)); else STALL=0; fi
MAXSTALL="$(cfg_get engine.goal.max_stall_iterations 10)"; MAXSTALL="${MAXSTALL:-10}"; case "$MAXSTALL" in ''|*[!0-9]*) MAXSTALL=10;; esac
{ echo "ITER=$ITER"; echo "STATUS=not_met"; echo "STALL=$STALL"; echo "LAST_REASON=$REASON"; } > "$STATE" 2>/dev/null || true
if [ "$MAXSTALL" -gt 0 ] && [ "$STALL" -ge "$MAXSTALL" ] 2>/dev/null; then
  bash "$SKILL_DIR/scripts/notify.sh" warn "ultraloop stalled" "same blocker repeated ${STALL} times (no progress) → stop allowed. Human input needed: $REASON" >/dev/null 2>&1 || true
  allow
fi
block "[$ITER/$MAXIT · stall $STALL/$MAXSTALL] Not finished yet. $REASON — continue the remaining work (/ultraloop loop)."
