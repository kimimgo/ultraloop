#!/usr/bin/env bash
# ultraloop console_modal.sh — 터미널 앞에 사람이 있을 때의 폴백 승인 모달
# Discord 게이트웨이 봇을 못 쓰는 환경에서 /dev/tty 로 직접 Y/N 을 묻는다.
#
# 사용법: console_modal.sh "<question>" "<risk>"
#
# 종료코드(approval_queue 계약과 일치): 0=Y(승인) / 1=N(거부) / 4=hold(타임아웃·무응답)
set -uo pipefail

QUESTION="${1:-승인이 필요합니다.}"
RISK="${2:-unknown}"
TIMEOUT="${ULTRALOOP_CONSOLE_TIMEOUT:-120}"   # 초 단위, read -t 로 사용

# tty 가 없으면(스크립트/CI) 사람이 답할 수 없으므로 즉시 hold.
if [ ! -e /dev/tty ] || [ ! -r /dev/tty ]; then
  echo "[console_modal] no tty → hold" >&2
  exit 4
fi

{
  echo ""
  echo "──────────────────────────────────────────────"
  echo " ⚠️  ultraloop 승인 요청 (risk: ${RISK})"
  echo "──────────────────────────────────────────────"
  echo " ${QUESTION}"
  echo ""
  echo " [Y] 승인   [N] 거부   (${TIMEOUT}s 내 무응답 시 보류)"
  echo -n " 선택 > "
} >/dev/tty

ANSWER=""
# read -t 로 타임아웃. 입력은 /dev/tty 에서 직접 읽는다.
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
