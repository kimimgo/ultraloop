#!/usr/bin/env bash
# cost_guard.sh — §15 cost/time/loop cap check. Called every loop ① + in the goal gate.
#   exit 0 = headroom left (continue)
#   exit 7 = budget-stop (cap exceeded → safe stop)
# Checks: wall-clock · loop count · (when possible) CI minutes. Tokens are delegated to the session limit (best-effort here).
# Non-determinism: the harness knows the real token accounting. Here we deterministically block only *what can definitely be counted*.

set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
STATE_DIR="$(ue_state_dir)"
START="$STATE_DIR/run-start"; LOOPS="$STATE_DIR/loop-count"

now=$(date +%s)
# Args: --no-tick = check only, no count increment (for the goal Stop gate) · --reset = clear run state. Default = tick (one loop ①).
TICK=1
case "${1:-}" in
  --no-tick) TICK=0 ;;
  --reset)   # ★ Call when a new run starts — leftover run-start residue makes a new run hit the wall-clock cap from its very first loop.
    #   #4: the worktree drain confirmation is per-run — a new run must re-ask the human.
    rm -f "$START" "$LOOPS" "$STATE_DIR/heartbeat" "$STATE_DIR"/goal-*.state "$STATE_DIR/worktree-drain-confirm" 2>/dev/null || true
    ue_log "run state reset (run-start·loop-count·heartbeat·goal state·worktree confirm)"; exit 0 ;;
esac
# Auto-reset on full-board completion: if the previous run ended with goal met (STATUS=met), treat this as a new run and self-clean.
#   budget-stop residue has unclear intent (resume vs new run) so it is not auto-cleaned — for a new run, --reset must come first (loop entry gate).
if [ "$TICK" = 1 ] && grep -q '^STATUS=met' "$STATE_DIR/goal-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1).state" 2>/dev/null; then
  rm -f "$START" "$LOOPS" "$STATE_DIR/heartbeat" "$STATE_DIR"/goal-*.state "$STATE_DIR/worktree-drain-confirm" 2>/dev/null || true
  ue_log "previous run completed (goal met) detected → run state auto-reset"
fi
# Record start time on first call
[ -f "$START" ] || echo "$now" > "$START"
start=$(cat "$START" 2>/dev/null || echo "$now")
# loop count (incremented only in tick mode; cnt for cap checks is always read)
cnt=0; [ -f "$LOOPS" ] && cnt=$(cat "$LOOPS" 2>/dev/null || echo 0)
[ "$TICK" = 1 ] && { cnt=$((cnt+1)); echo "$cnt" > "$LOOPS"; }

MAXH="$(cfg_get budgets.max_wall_clock_hours 24)";  MAXH="${MAXH:-24}"
MAXL="$(cfg_get budgets.max_loops 0)";              MAXL="${MAXL:-0}"

# wall-clock cap
if [ "$MAXH" -gt 0 ] 2>/dev/null; then
  elapsed=$(( (now - start) / 3600 ))
  if [ "$elapsed" -ge "$MAXH" ]; then
    ue_log "budget-stop: wall-clock ${elapsed}h ≥ ${MAXH}h"; exit 7
  fi
fi
# loop count cap (0 = unlimited)
if [ "$MAXL" -gt 0 ] 2>/dev/null && [ "$cnt" -ge "$MAXL" ]; then
  ue_log "budget-stop: loops ${cnt} ≥ ${MAXL}"; exit 7
fi

# dead-man switch: warn (not block) when there has been no progress since the last heartbeat
DMS="$(cfg_get budgets.dead_mans_switch_minutes 30)"; DMS="${DMS:-30}"
HB="$STATE_DIR/heartbeat"
if [ -f "$HB" ] && [ -n "$(find "$HB" -mmin +"$DMS" 2>/dev/null)" ]; then
  bash "$SDIR/notify.sh" warn "ultraloop dead-man" "no progress for ${DMS} min — possible stall or hang" >/dev/null 2>&1 || true
fi

exit 0
