#!/usr/bin/env bash
# ultraloop notify.sh — Outbound-only Discord notification (fire-and-continue)
# SPEC v0.3 §13. Notifications are non-blocking (never kill the loop) — exit 0 always.
#
# usage: notify.sh <level> <title> <message> [evidence_path]
#   level ∈ info | warn | error | approval-pending | heartbeat
#
# Design: compatible with corporate DLP (egress-only) environments — only POSTs an embed to a channel via the REST API.
#   The token is read only from the environment variable named by token_env in config (no hardcoding).
#   When discord.enabled=false or the token is missing, falls through to stdout and exits cleanly.
#
# ⚠️ the urllib fallback requires a User-Agent header to avoid Cloudflare 403 error 1010.
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

# tiny YAML helper: reads a single discord.<key> line flatly (based on nested indentation).
cfg() {
  local key="$1"
  [ -f "$CONFIG" ] || return 0
  awk -v k="$key" '
    /^discord:/ {ind=1; next}
    ind==1 {
      if ($0 ~ /^[^[:space:]]/) {ind=0; next}   # end of discord block
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

# graceful degrade: disabled / no token / no channel → print to stdout and exit
if [ "${ENABLED,,}" = "false" ] || [ -z "$TOKEN" ] || [ -z "$CHANNEL" ]; then
  echo "[ultraloop:${LEVEL}] ${TITLE} — ${MESSAGE}${EVIDENCE:+ (evidence: ${EVIDENCE})}"
  exit 0
fi

DESC="$MESSAGE"
[ -n "$EVIDENCE" ] && DESC="${DESC}"$'\n'"evidence: ${EVIDENCE}"

# JSON-safe encoding via python3 (quote/newline escaping). The payload is built here.
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
  # python3 urllib fallback — User-Agent required (avoids Cloudflare 1010)
  python3 - "$URL" "$TOKEN" "$PAYLOAD" "$UA" <<'PY' 2>/dev/null \
    || echo "[ultraloop:${LEVEL}] (urllib notify failed) ${TITLE} — ${MESSAGE}"
import sys, urllib.request
url, token, payload, ua = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
req = urllib.request.Request(url, data=payload.encode("utf-8"), method="POST")
req.add_header("Authorization", "Bot " + token)
req.add_header("Content-Type", "application/json")
req.add_header("User-Agent", ua)  # ⚠️ without it: 403 error 1010
urllib.request.urlopen(req, timeout=10).read()
PY
fi

exit 0
