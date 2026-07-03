#!/usr/bin/env bash
# e2e_up.sh <issue#> — lane-isolated real deployment (the up half of pre-merge E2E). Wait for health → seed.
#   per lane: compose project-name=ue-<issue#> · dynamic port (base_port+issue) · volume isolation.
# Non-deterministic part: with runner=auto compose is preferred, else the single README command. Actual seeding/health is reinforced by the agent.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; PROJ="ue-${ISSUE}"
BASE="$(cfg_get e2e.base_port 14000)"; PORT=$((BASE + (ISSUE % 1000)))
RUNNER="$(cfg_get e2e.runner auto)"
TIMEOUT="$(cfg_get e2e.health_timeout_seconds 120)"
export UE_PORT="$PORT" UE_PROJECT="$PROJ" UE_LANE="$ISSUE"
echo "[e2e up] project=$PROJ port=$PORT runner=$RUNNER"

# secret injection (.env.e2e) — never commit plaintext
SECRETS="$(cfg_get e2e.secrets_file .env.e2e)"
[ -f "$SECRETS" ] && echo "  · secrets: $SECRETS (injected)" || echo "  · no secrets file ($SECRETS) — create one from vault/GH Secrets if needed"

RAN_COMPOSE=0
if { [ "$RUNNER" = "auto" ] || [ "$RUNNER" = "docker_compose" ]; } && command -v docker >/dev/null 2>&1 && ls docker-compose*.y*ml compose*.y*ml >/dev/null 2>&1; then
  ENVF=(); [ -f "$SECRETS" ] && ENVF=(--env-file "$SECRETS")   # inject secrets into containers only (avoid exposing them in the shell env)
  UE_PORT="$PORT" UE_LANE="$ISSUE" docker compose -p "$PROJ" "${ENVF[@]}" up -d 2>/dev/null || { ue_log "compose up failed — check the docker daemon and compose file; inspect with docker compose -p $PROJ logs"; exit 1; }
  echo "  · compose up (project=$PROJ, lane=$ISSUE)"; RAN_COMPOSE=1
else
  echo "  · falling back to single-command README startup — the agent runs the startup command from README (rules/readme.md contract)"
fi

# health wait (best-effort): check that the port is open
echo "  · waiting for health (≤${TIMEOUT}s) on :$PORT"
for _ in $(seq 1 "$TIMEOUT"); do
  (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && { echo "  ✓ port $PORT up"; exit 0; }
  sleep 1
done
# compose started but health timed out = deployment failure (no silent success). In README fallback mode the agent
# starts the app itself, so an unopened port here is normal → delegate with exit 0 (flake retries live in e2e_run/orchestrator).
if [ "$RAN_COMPOSE" = 1 ]; then ue_log "compose health timeout (:$PORT) — deployment failed; inspect container logs with docker compose -p $PROJ logs"; exit 1; fi
ue_log "README fallback mode — startup is performed by the agent (waiting on :$PORT delegated)"
exit 0
