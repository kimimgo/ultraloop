#!/usr/bin/env bash
# ultraloop console_modal.sh — fallback approval modal for when a human is at the terminal
# In environments where the Discord gateway bot cannot be used, asks Y/N directly via /dev/tty.
#
# usage: console_modal.sh "<question>" "<risk>"
#
# exit codes (matching the approval_queue contract): 0=Y (approve) / 1=N (reject) / 4=hold (timeout/no answer)
set -uo pipefail

QUESTION="${1:-Approval required.}"
RISK="${2:-unknown}"
TIMEOUT="${ULTRALOOP_CONSOLE_TIMEOUT:-120}"   # seconds, used with read -t

# Without a tty (script/CI) no human can answer, so hold immediately.
if [ ! -e /dev/tty ] || [ ! -r /dev/tty ]; then
  echo "[console_modal] no tty → hold" >&2
  exit 4
fi

{
  echo ""
  echo "──────────────────────────────────────────────"
  echo " ⚠️  ultraloop approval request (risk: ${RISK})"
  echo "──────────────────────────────────────────────"
  echo " ${QUESTION}"
  echo ""
  echo " [Y] approve   [N] reject   (held if no answer within ${TIMEOUT}s)"
  echo -n " choice > "
} >/dev/tty

ANSWER=""
# timeout via read -t. Input is read directly from /dev/tty.
if ! read -t "$TIMEOUT" -r ANSWER </dev/tty; then
  echo "" >/dev/tty
  echo "[console_modal] timeout/no-answer → hold" >&2
  exit 4
fi

case "${ANSWER,,}" in
  y|yes|ㅛ)
    echo "[console_modal] decision=Y" >&2
    exit 0 ;;
  n|no|ㅜ)
    echo "[console_modal] decision=N" >&2
    exit 1 ;;
  *)
    echo "[console_modal] unrecognized '${ANSWER}' → hold" >&2
    exit 4 ;;
esac
