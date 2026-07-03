#!/usr/bin/env bash
# worker_spawn.sh — start, direct, and observe multi-repo workers (tmux cc sessions) (multi-repo-orchestration.md §4·§6)
#   spawn authority is meta-only — workers/hooks must never call this script (recursive spawn forbidden).
# usage:
#   worker_spawn.sh list                      # config repos + session liveness
#   worker_spawn.sh spawn [--all|<name>] [--dry-run]   # start with cap, stagger, and worktree isolation
#   worker_spawn.sh inject <name> <task_file>          # one-line send-keys + capture-pane ack + retry
#   worker_spawn.sh capture <name> [lines]             # observe the worker screen
# exit 0=ok · 2=missing config/args · 4=concurrency cap reached · 6=injection failed (no ack)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

SOCK="$(cfg_get orchestration.tmux_socket "")"
SPAWN="$(cfg_get orchestration.spawn tmux_new_session)"
CHANNEL="$(cfg_get orchestration.channel auto)"
# message broker (optional): delivers directives to workers durably. Falls back to send-keys when empty.
HUB="${ULTRALOOP_BROKER_URL:-$(cfg_get orchestration.broker_url '')}"
# external session manager CLI (optional): session name = repo basename (no prefix → attach-compatible with that CLI).
#   Empty means plain tmux. CC startup happens here (works even when the session manager does not launch CC).
SESSMGR="$(cfg_get orchestration.session_mgr_cmd '')"
SM_MODE=0; case "$SPAWN" in session_mgr) [ -n "$SESSMGR" ] && command -v "$SESSMGR" >/dev/null 2>&1 && SM_MODE=1;; esac
TMUX_CMD=(tmux); [ "$SM_MODE" = 0 ] && [ -n "$SOCK" ] && TMUX_CMD=(tmux -L "$SOCK")
PERM="$(cfg_get orchestration.permission_mode bypassPermissions)"
MAXW="$(cfg_get orchestration.max_concurrent_workers 2)"
STAG="$(cfg_get orchestration.stagger_seconds 20)"
REPOS_JSON="$(cfg_get repos "[]")"
hub_ok() { curl -s -m 2 "$HUB/health" 2>/dev/null | grep -q '"status":"ok"'; }

repo_field() { # repo_field <name> <key> [default]
  printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
n,k,d=sys.argv[1],sys.argv[2],sys.argv[3] if len(sys.argv)>3 else ""
for r in json.load(sys.stdin):
    if r.get("name")==n or r.get("name","").split("/")[-1]==n: print(r.get(k,d)); break
else: print(d)' "$1" "$2" "${3:-}"
}
repo_names() { printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
for r in json.load(sys.stdin): print(r["name"])'; }
sess_of() { [ "$SM_MODE" = 1 ] && basename "$1" || echo "ul-$(basename "$1")"; }
alive() { "${TMUX_CMD[@]}" has-session -t "$1" 2>/dev/null; }
live_count() { local n=0; while read -r R; do alive "$(sess_of "$R")" && n=$((n+1)); done < <(repo_names); echo "$n"; }

cmd="${1:-list}"; shift || true
# ★ recursion-guard hard block (code, not just a comment) — ULTRALOOP_WORKER=1 is planted into worker sessions at spawn.
#   If a worker/its hook calls spawn·inject, block it here (spawn authority is meta-only). list/capture are reads and allowed.
if [ "${ULTRALOOP_WORKER:-}" = "1" ] && { [ "$cmd" = "spawn" ] || [ "$cmd" = "inject" ]; }; then
  echo "✗ $cmd forbidden in a worker session — spawn authority is meta-only (recursive spawn blocked)"; exit 3
fi
case "$cmd" in
list)
  echo "workers (socket=${SOCK:-default}, cap=$MAXW):"
  repo_names | while read -r R; do
    S="$(sess_of "$R")"; alive "$S" && st="● live" || st="○ down"
    echo "  $st  $S  ($R  path=$(repo_field "$R" path '?'))"
  done ;;

spawn)
  TARGET="${1:-}"; DRY=0; [ "$TARGET" = "--dry-run" ] && { DRY=1; TARGET="--all"; }
  [ "${2:-}" = "--dry-run" ] && DRY=1
  [ -n "$TARGET" ] || TARGET="--all"
  repo_names | while read -r R; do
    [ "$TARGET" != "--all" ] && [ "$R" != "$TARGET" ] && [ "$(basename "$R")" != "$TARGET" ] && continue
    S="$(sess_of "$R")"; P="$(repo_field "$R" path "")"
    P="${P/#\~/$HOME}"
    alive "$S" && { echo "  ✓ $S already live (idempotent)"; continue; }
    [ -n "$P" ] && [ -d "$P" ] || { echo "  ✗ $R path unset or missing ($P) — set repos[].path in config"; continue; }
    if [ "$(live_count)" -ge "$MAXW" ]; then echo "  ✗ concurrency cap ($MAXW) reached — $R held (usage and tmux load guard); retry after a worker session ends"; exit 4; fi
    # host-occupancy conflict → worktree isolation (isolation:worktree set explicitly, or host cwd is inside the repo)
    WANT_ISO="$(repo_field "$R" isolation "")"
    case "$PWD/" in "$P"/*) WANT_ISO=worktree;; esac
    if [ "$WANT_ISO" = "worktree" ]; then
      WT="$(dirname "$P")/$(basename "$P")-ul-worker"
      if [ ! -d "$WT" ]; then
        BR="ul/$(basename "$P")-worker"; DEFB="$(cfg_get default_branch main)"
        [ "$DRY" = 1 ] && echo "DRY: git -C $P worktree add $WT -b $BR $DEFB" || \
          git -C "$P" worktree add "$WT" -b "$BR" "$DEFB" 2>/dev/null || \
          git -C "$P" worktree add "$WT" "$BR" 2>/dev/null || { echo "  ✗ $R worktree isolation failed — check existing worktrees and branch conflicts with git worktree list"; continue; }
      fi
      P="$WT"; echo "  · $R host occupied → worktree isolation: $P"
    fi
    if [ "$DRY" = 1 ]; then echo "DRY: ${TMUX_CMD[*]} new-session -d -s $S -c $P  ULTRALOOP_WORKER=1 claude --permission-mode $PERM"; continue; fi
    # ULTRALOOP_WORKER=1: marks the whole worker CC process tree → hard-blocks recursive worker_spawn calls.
    "${TMUX_CMD[@]}" new-session -d -s "$S" -c "$P" "ULTRALOOP_WORKER=1 claude --permission-mode $PERM" \
      && echo "  ✓ spawned $S (cwd=$P)" || { echo "  ✗ $S failed to start — check tmux availability and the claude CLI"; continue; }
    # The external session manager does not need to issue separate keepalive commands — persistence comes from the tmux session itself.
    # CC in a fresh worktree/clone stops at the folder-trust dialog (even bypassPermissions cannot skip it — measured
    # in full-cycle E2E). We just created this directory, so auto-trust is safe. This step also waits until the TUI is ready (status bar).
    for _t in 1 2 3 4 5 6; do
      sleep 5
      PANE="$("${TMUX_CMD[@]}" capture-pane -t "$S" -p 2>/dev/null)"
      printf '%s' "$PANE" | grep -q "trust this folder" \
        && { "${TMUX_CMD[@]}" send-keys -t "$S" Enter; echo "  · folder trust auto-confirmed"; }
      printf '%s' "$PANE" | grep -q "shift+tab" && { echo "  · TUI ready"; break; }
    done
    ue_log "stagger ${STAG}s (no simultaneous startup — guard against usage spikes and server load)"; sleep "$STAG"
  done ;;

inject)
  NAME="${1:-}"; FILE="${2:-}"
  [ -n "$NAME" ] && [ -f "$FILE" ] || { echo "usage: inject <name> <task_file>"; exit 2; }
  S="$(sess_of "$NAME")"; alive "$S" || { echo "✗ $S session not found — run spawn first"; exit 2; }
  MSG="Read the file $FILE and carry out its instructions exactly."   # no multi-line direct injection (appendix B)
  # Channel priority 1 = message broker (durable messaging: persisted to the inbox; the worker receives it at SessionStart/poll).
  #   After a successful delivery, send-keys is only a wake-up bonus (even if it fails, the message stays in the inbox — nothing is lost).
  #   Used only when a broker is configured (ULTRALOOP_BROKER_URL/orchestration.broker_url) and reachable.
  if [ -n "$HUB" ] && [ "$CHANNEL" != "send_keys" ] && hub_ok; then
    BODY="$(python3 -c 'import json,sys; print(json.dumps({"from":sys.argv[1],"to":sys.argv[2],"body":sys.argv[3]}))' "ultraloop-meta" "$S" "$MSG")"
    if curl -fsS -m 3 -X POST "$HUB/team/messages" -H 'content-type: application/json' -d "$BODY" >/dev/null 2>&1; then
      "${TMUX_CMD[@]}" send-keys -t "$S" "Carry out the directive received from the message broker inbox (GET $HUB/team/inbox/$S?consume=true)." Enter 2>/dev/null || true
      echo "✓ injected → $S (broker durable + nudge)"; exit 0
    fi
    ue_log "broker send failed → falling back to send_keys"
  fi
  for try in 1 2 3; do
    "${TMUX_CMD[@]}" send-keys -t "$S" "$MSG" Enter; sleep 3
    "${TMUX_CMD[@]}" capture-pane -t "$S" -p 2>/dev/null | grep -qF "$FILE" \
      && { echo "✓ injected → $S (send-keys ack try=$try)"; exit 0; }
    ue_log "no ack (try=$try) — retrying"
  done
  echo "✗ $S injection ack failed (3 tries) — check state with capture, then intervene manually"; exit 6 ;;

capture)
  NAME="${1:-}"; [ -n "$NAME" ] || { echo "usage: capture <name> [lines]"; exit 2; }
  "${TMUX_CMD[@]}" capture-pane -t "$(sess_of "$NAME")" -p 2>/dev/null | tail -n "${2:-30}" ;;

*) echo "usage: worker_spawn.sh list|spawn|inject|capture"; exit 2 ;;
esac
