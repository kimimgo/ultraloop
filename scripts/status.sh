#!/usr/bin/env bash
# status.sh [--refresh|--line] — loop progress (board Done ratio + loop count/elapsed) as a one-line bar.
#   --refresh : tallies the board (SoT) via gh and writes the status.json cache (slow — called only from loop ①).
#   --line    : reads status.json and prints a one-line progress string (no graphql — for statusline/hook, fast). Default.
# Cache location = ue_state_dir/status.json (per repo, /tmp — independent of git). The statusline may read this file directly.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
STATE_DIR="$(ue_state_dir)"; SJ="$STATE_DIR/status.json"
MODE="${1:---line}"

_bar() {  # $1=pct $2=width → progress bar (filled ▓ / empty ░)
  local p="${1:-0}" w="${2:-10}" n i s=""; p="${p%.*}"; [ -z "$p" ] && p=0
  n=$(( (p * w + 50) / 100 )); [ "$n" -gt "$w" ] && n=$w; [ "$n" -lt 0 ] && n=0
  i=0; while [ "$i" -lt "$w" ]; do [ "$i" -lt "$n" ] && s="$s▓" || s="$s░"; i=$((i+1)); done
  printf '%s' "$s"
}

if [ "$MODE" = "--refresh" ]; then
  REPO="$(ue_repo)"; PROJ="$(cfg_get roadmap.project_number "")"
  TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
  LOOPS=0; [ -f "$STATE_DIR/loop-count" ] && LOOPS="$(cat "$STATE_DIR/loop-count" 2>/dev/null || echo 0)"
  ELAP=0; [ -f "$STATE_DIR/run-start" ] && ELAP=$(( ( $(date +%s) - $(cat "$STATE_DIR/run-start" 2>/dev/null || date +%s) ) / 60 ))
  DONE=0; TOTAL=0; PROG=0; BLK=0
  if [ -n "$PROJ" ] && command -v gh >/dev/null 2>&1; then
    read -r DONE TOTAL PROG BLK < <(GH_TOKEN="${!TOKEN_ENV:-${GH_TOKEN:-}}" gh project item-list "$PROJ" --owner "${REPO%%/*}" --format json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); items=d.get("items", d if isinstance(d,list) else [])
except Exception:
    items=[]
def s(it): return str(it.get("status",""))
done=sum(1 for it in items if s(it).lower()=="done")
prog=sum(1 for it in items if s(it)=="In-Progress")
blk =sum(1 for it in items if s(it)=="Blocked")
print(done, len(items), prog, blk)' 2>/dev/null || echo "0 0 0 0")
  fi
  DONE="${DONE:-0}"; TOTAL="${TOTAL:-0}"; PROG="${PROG:-0}"; BLK="${BLK:-0}"
  PCT=0; [ "$TOTAL" -gt 0 ] 2>/dev/null && PCT=$(( DONE * 100 / TOTAL ))
  printf '{"pct":%d,"done":%d,"total":%d,"in_progress":%d,"blocked":%d,"loops":%d,"elapsed_min":%d,"repo":"%s","ts":%d}\n' \
    "$PCT" "$DONE" "$TOTAL" "$PROG" "$BLK" "$LOOPS" "$ELAP" "$REPO" "$(date +%s)" > "$SJ" 2>/dev/null \
    && ue_log "status.json updated: ${PCT}% (${DONE}/${TOTAL})" || ue_log "status.json write failed — state dir may be missing or unwritable; check $STATE_DIR"
fi

# --line (default): status.json → one line (no prefix; the caller prepends e.g. "⟳ ultraloop")
[ -f "$SJ" ] || { echo "(board not yet tallied)"; exit 0; }
vals="$(python3 -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
print("%d %d %d %d %d %d %d"%(d.get("pct",0),d.get("done",0),d.get("total",0),d.get("in_progress",0),d.get("blocked",0),d.get("loops",0),d.get("elapsed_min",0)))
' "$SJ" 2>/dev/null)" || { echo "(board not yet tallied)"; exit 0; }
read -r PCT DONE TOTAL PROG BLK LOOPS EL <<<"$vals"
EH=$(( ${EL:-0} / 60 )); EM=$(( ${EL:-0} % 60 ))
LINE="[$(_bar "${PCT:-0}" 10)] ${PCT:-0}% · ${DONE:-0}/${TOTAL:-0}"
[ "${PROG:-0}" -gt 0 ] && LINE="$LINE · ${PROG}▶"
[ "${BLK:-0}" -gt 0 ]  && LINE="$LINE · ${BLK}⛔"
LINE="$LINE · loop${LOOPS:-0}"
if [ "${EL:-0}" -gt 0 ]; then [ "$EH" -gt 0 ] && LINE="$LINE ${EH}h${EM}m" || LINE="$LINE ${EM}m"; fi
echo "$LINE"
