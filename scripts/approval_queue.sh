#!/usr/bin/env bash
# approval_queue.sh — async approval queue (high-risk, non-blocking). File based.
#   enqueue <action> <risk> [ttl_min]  : add to the queue + notify (parking the lane is done by the caller on the board)
#   drain                               : check resolved items → 0=announce pending Y items to process / non-blocking
#   wait <id> [ttl_min]                 : wait for the result of a specific item (gateway bot/console)
#   exit 0=Y approved · 1=N rejected · 4=hold (no answer within TTL → escalation/defer)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
QDIR="${TMPDIR:-/tmp}/ultraloop-approvals"; mkdir -p "$QDIR"
TTL_DEF="$(cfg_get discord.approval_ttl_minutes 120)"
CMD="${1:-drain}"

new_id() { printf 'apr-%s-%s' "$(date +%s)" "$$"; }

case "$CMD" in
  enqueue)
    ACTION="${2:?action}"; RISK="${3:-high}"; TTL="${4:-$TTL_DEF}"
    ID="$(new_id)"
    { echo "id=$ID"; echo "action=$ACTION"; echo "risk=$RISK"; echo "ttl_min=$TTL"; echo "ts=$(date +%s)"; } > "$QDIR/$ID.pending"
    bash "$SDIR/notify.sh" approval-pending "ultraloop approval needed (high-risk)" "[$RISK] $ACTION — awaiting response (TTL ${TTL}m). This lane is Parked; other lanes continue." >/dev/null 2>&1 || true
    # if a gateway bot is available, post buttons (per-approval). Otherwise console/polling.
    if [ "$(cfg_get discord.mode gateway_bot)" = "gateway_bot" ] && command -v python3 >/dev/null 2>&1; then
      ( python3 "$SDIR/approve_bot.py" "$ID" "$ACTION" "$RISK" "$TTL" >/dev/null 2>&1 & ) || true
    fi
    echo "$ID"
    ;;
  drain)
    # report items whose result file (.result) has appeared. Non-blocking.
    found=0
    for r in "$QDIR"/*.result; do
      [ -e "$r" ] || continue
      id="$(basename "$r" .result)"; dec="$(head -1 "$r" 2>/dev/null)"
      echo "$id: $dec"; rm -f "$QDIR/$id.pending" 2>/dev/null; found=1
    done
    [ "$found" -eq 0 ] && echo "(no pending results to process)"
    exit 0
    ;;
  wait)
    ID="${2:?id}"; TTL="${3:-$TTL_DEF}"; deadline=$(( $(date +%s) + TTL*60 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if [ -f "$QDIR/$ID.result" ]; then
        case "$(head -1 "$QDIR/$ID.result")" in
          Y*|y*) exit 0 ;; N*|n*) exit 1 ;;
        esac
      fi
      sleep 5
    done
    # TTL exceeded → escalate + defer
    bash "$SDIR/notify.sh" warn "ultraloop approval TTL exceeded" "id=$ID no response (${TTL}m) → escalate/defer. Item moved to lower priority." >/dev/null 2>&1 || true
    exit 4
    ;;
  *) echo "usage: approval_queue.sh enqueue <action> <risk> [ttl] | drain | wait <id> [ttl]"; exit 1 ;;
esac
