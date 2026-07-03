#!/usr/bin/env bash
# e2e_run.sh <issue#> [scenario] — real-run scenario + captured evidence.
#   exit 0 = PASS · 1 = deterministic FAIL
# flake handling (REQ-E2E-6): transient failures (port/timeout/warm-up) get backoff retries (≤flake_retries);
#   only failure after all retries is a deterministic FAIL. A flake is not a strike.
#
# ★ This script only sets the *frame*. The actual click/shell/HTTP scenario and deterministic assertions are
#   performed by the agent via browser MCP / a separate shell session, and captured into e2e/reports/<date>-<item>.md.
#   (assets/e2e/scenario.template.md · report.template.md)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; SCN="${2:-default}"
RETRIES="$(cfg_get e2e.flake_retries 3)"; MAXMB="$(cfg_get e2e.screenshot_max_mb 2)"
REPORT_DIR="./e2e/reports"; mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/$(date +%Y%m%d)-issue${ISSUE}.md"

echo "[e2e run] issue=$ISSUE scenario=$SCN retries=$RETRIES report=$REPORT"
echo "  · agent to-do: run the scenario (web=browser MCP clicks+screenshots / CLI=separate shell / API=real HTTP)"
echo "  · deterministic assertions alongside (HTTP status · DB row counts · file existence · exit code)"
echo "  · compress screenshots <${MAXMB}MB → link/thumbnail in the report (no raw embeds, DLP)"

# What automation can catch: is the stack alive (port), and if a scenario script file exists, run it.
# Transient failures are retried. (The agent records the final PASS/FAIL verdict in the report; this script reflects it via its exit code.)
SCN_FILE="./e2e/scenarios/${SCN}.sh"
attempt=0
while :; do
  attempt=$((attempt+1))
  if [ -x "$SCN_FILE" ]; then
    if bash "$SCN_FILE"; then RC=0; else RC=$?; fi
  else
    # No scenario script: assume the agent ran the scenario interactively and judge by the final-result marker in the report.
    # Only the **PASS**/**FAIL** markers in the final-result section of report.template count — avoids partial matches
    # such as password/bypass and the PASS/FAIL guidance text in the step table. If neither exists (report unwritten), treat as FAIL.
    if grep -qE '\*\*PASS\*\*' "$REPORT" 2>/dev/null && ! grep -qE '\*\*FAIL\*\*' "$REPORT" 2>/dev/null; then RC=0; else RC=1; fi
  fi
  if [ "$RC" -eq 0 ]; then echo "  ✓ E2E PASS (attempt $attempt)"; exit 0; fi
  # possibly-transient failure → backoff retry
  if [ "$attempt" -lt "$RETRIES" ]; then
    ue_log "E2E failed (possibly transient) attempt=$attempt → backoff retry"; sleep $((attempt*3)); continue
  fi
  ue_log "E2E deterministic FAIL (retries $RETRIES exhausted) → apply e2e:fail + file a bug issue"
  exit 1
done
