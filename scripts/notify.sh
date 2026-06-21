#!/usr/bin/env bash
# ultraloop notify.sh — Outbound-only Discord notification (fire-and-continue)
# SPEC v0.3 §13. 알림은 비차단(루프를 절대 죽이지 않음) — exit 0 always.
#
# 사용법: notify.sh <level> <title> <message> [evidence_path]
#   level ∈ info | warn | error | approval-pending | heartbeat
#
# 설계: 회사 DLP(egress-only) 환경 호환 — REST API로 채널에 임베드 POST만 한다.
#   토큰은 config의 token_env 가 가리키는 환경변수에서만 읽는다(하드코딩 금지).
#   discord.enabled=false 거나 토큰이 없으면 stdout으로 떨어뜨리고 정상 종료.
#
# ⚠️ urllib 폴백은 Cloudflare 403 error 1010 회피를 위해 User-Agent 헤더 필수.
set -uo pipefail

LEVEL="${1:-info}"
TITLE="${2:-ultraloop}"
MESSAGE="${3:-}"
EVIDENCE="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${ULTRALOOP_CONFIG:-${SCRIPT_DIR}/../ultraloop.config.yaml}"
UA='DiscordBot (https://github.com/ultraloop, 1.0)'

# color by level (Discord embed decimal colors)
case "$LEVEL" in
  info)             COLOR=3066993  ;;  # green
  warn)             COLOR=16776960 ;;  # yellow
  error)            COLOR=15158332 ;;  # red
  approval-pending) COLOR=3447003  ;;  # blue
  heartbeat)        COLOR=3447003  ;;  # blue
  *)                COLOR=9807270  ;;  # grey (unknown level)
esac

# 아주 작은 YAML 헬퍼: discord.<key> 한 줄을 평면적으로 읽는다(중첩 들여쓰기 기준).
cfg() {
  local key="$1"
  [ -f "$CONFIG" ] || return 0
  awk -v k="$key" '
    /^discord:/ {ind=1; next}
    ind==1 {
      if ($0 ~ /^[^[:space:]]/) {ind=0; next}   # discord 블록 종료
      line=$0; sub(/^[[:space:]]+/,"",line)
      if (line ~ "^" k ":") {
        sub("^" k ":[[:space:]]*","",line)
        gsub(/^["'\''[:space:]]+|["'\''[:space:]]+$/,"",line)
        print line; exit
      }
    }
  ' "$CONFIG"
}

ENABLED="$(cfg enabled)"
TOKEN_ENV="$(cfg token_env)"; TOKEN_ENV="${TOKEN_ENV:-ULTRALOOP_DISCORD_BOT_TOKEN}"
CHANNEL="$(cfg notify_channel_id)"
TOKEN="${!TOKEN_ENV:-}"

# graceful degrade: 비활성/토큰없음/채널없음 → stdout 출력 후 종료
if [ "${ENABLED,,}" = "false" ] || [ -z "$TOKEN" ] || [ -z "$CHANNEL" ]; then
  echo "[ultraloop:${LEVEL}] ${TITLE} — ${MESSAGE}${EVIDENCE:+ (evidence: ${EVIDENCE})}"
  exit 0
fi

DESC="$MESSAGE"
[ -n "$EVIDENCE" ] && DESC="${DESC}"$'\n'"근거: ${EVIDENCE}"

# JSON 안전 인코딩은 python3 로(따옴표/개행 escaping). payload 파일을 임시로 만든다.
PAYLOAD="$(python3 - "$TITLE" "$DESC" "$COLOR" <<'PY'
import json, sys
title, desc, color = sys.argv[1], sys.argv[2], int(sys.argv[3])
print(json.dumps({"embeds": [{"title": title[:256], "description": desc[:4096], "color": color}]}))
PY
)"

URL="https://discord.com/api/v10/channels/${CHANNEL}/messages"

if command -v curl >/dev/null 2>&1; then
  curl -fsS -X POST "$URL" \
    -H "Authorization: Bot ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${UA}" \
    --data "$PAYLOAD" >/dev/null 2>&1 \
    || echo "[ultraloop:${LEVEL}] (curl notify failed) ${TITLE} — ${MESSAGE}"
else
  # python3 urllib 폴백 — User-Agent 필수(Cloudflare 1010 회피)
  python3 - "$URL" "$TOKEN" "$PAYLOAD" "$UA" <<'PY' 2>/dev/null \
    || echo "[ultraloop:${LEVEL}] (urllib notify failed) ${TITLE} — ${MESSAGE}"
import sys, urllib.request
url, token, payload, ua = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
req = urllib.request.Request(url, data=payload.encode("utf-8"), method="POST")
req.add_header("Authorization", "Bot " + token)
req.add_header("Content-Type", "application/json")
req.add_header("User-Agent", ua)  # ⚠️ 없으면 403 error 1010
urllib.request.urlopen(req, timeout=10).read()
PY
fi

exit 0
