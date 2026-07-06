#!/usr/bin/env bash
# crew_notify.sh <target-session> "<message>" — ACTIVE team message: durable cc-hub send + WAKE the target.
#
# Why: a plain cc-hub send is passive — the target only sees it at its next SessionStart/peek (up to
#   idle_wakeup_seconds away). This sends the durable payload AND wakes the target so it reacts NOW.
#   The message is a low-latency POINTER/nudge ("look at card #N"); the durable state is on the board (SoT),
#   so a missed wake loses nothing — the target still recovers via its SessionStart inbox + the board.
#
# Wake = STANDARD, not a bonus (this is the fix for the passive-comms gap). Best-effort: send-keys failure is non-fatal.
# ★ No recursion: send-keys a one-liner only — never spawns a session (crew's star topology: main↔lanes, lanes never spawn).
#
# usage: crew_notify.sh <project~slug|main> "<message>"     (FROM defaults to $TEAM_NAME, else "main")
# exit 0 = delivered (queued at minimum) · 2 = arg error
set -uo pipefail
TARGET="${1:-}"; MSG="${2:-}"
[ -n "$TARGET" ] && [ -n "$MSG" ] || { echo "usage: crew_notify.sh <target-session> \"<message>\""; exit 2; }

CCHUB="${TCTL_CCHUB_BASE:-http://127.0.0.1:28797}"
FROM="${TEAM_NAME:-main}"
TMUX_BIN=(tmux); [ -n "${TMUX_SOCK:-}" ] && TMUX_BIN=(tmux -S "$TMUX_SOCK")

# 1) durable payload → cc-hub inbox (survives even if the wake misses)
BODY="$(python3 -c 'import json,sys;print(json.dumps({"from":sys.argv[1],"to":sys.argv[2],"body":sys.argv[3]}))' "$FROM" "$TARGET" "$MSG" 2>/dev/null)"
if ! curl -fsS -m 3 -X POST "$CCHUB/team/messages" -H 'content-type: application/json' -d "$BODY" >/dev/null 2>&1; then
  echo "crew_notify: cc-hub send failed ($CCHUB) — target recovers via SessionStart/board" >&2
fi

# 2) WAKE (standard): nudge the target to check its inbox NOW. Best-effort — a live session at a prompt reacts immediately.
if "${TMUX_BIN[@]}" has-session -t "$TARGET" 2>/dev/null; then
  if "${TMUX_BIN[@]}" send-keys -t "$TARGET" "새 team 메시지 도착 — team_inbox_peek 로 확인하고 board 에 반영" Enter 2>/dev/null; then
    echo "✓ notified $TARGET (cc-hub inbox + wake)"
  else
    echo "✓ notified $TARGET (cc-hub inbox; wake send-keys failed — recovers via SessionStart/board)"
  fi
else
  echo "✓ queued for $TARGET (cc-hub inbox; session not live — delivered at its next SessionStart)"
fi
exit 0
