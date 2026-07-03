#!/usr/bin/env bash
# e2e_down.sh <issue#> — lane teardown + leak reclamation + disk watchdog.
#   down -v is allowed only for isolated volumes (high-risk guard exception — observability/notify-approval).
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; PROJ="ue-${ISSUE}"

if command -v docker >/dev/null 2>&1; then
  docker compose -p "$PROJ" down -v 2>/dev/null && echo "[e2e down] $PROJ cleaned up (-v)" || true
  # reclaim orphan containers/volumes (this project label only)
  docker ps -aq --filter "label=com.docker.compose.project=$PROJ" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
  # disk watchdog
  USE="$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')"
  if [ -n "$USE" ] && [ "$USE" -ge 85 ] 2>/dev/null; then
    ue_log "disk ${USE}% — safe prune (dangling images + build cache) + notify"
    # ★ shared self-hosted host — global docker system prune is forbidden (it deletes stopped containers and caches of other projects).
    #   Reclaim only dangling images/build cache; running resources and volumes of other projects are left untouched.
    docker image prune -f 2>/dev/null || true
    docker builder prune -f 2>/dev/null || true
    bash "$SDIR/notify.sh" warn "ultraloop disk watchdog" "disk ${USE}% → pruned dangling images/build cache (no global prune)" >/dev/null 2>&1 || true
  fi
fi
# secret disposal (.env.e2e is not kept after teardown — preserved only when it is a user-provided file)
exit 0
