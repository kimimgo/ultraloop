#!/usr/bin/env bash
# stop-inbox-check.sh — ultraloop crew Stop hook: turn-end team-inbox check (ACTIVE collaboration).
#
# Problem it fixes: team messages land in the cc-hub inbox but a session only reads them at SessionStart / when it
#   remembers to peek — so a session that finishes a turn and goes idle can miss a message for up to
#   idle_wakeup_seconds. This hook makes the check happen at EVERY turn end: if there are unconsumed messages,
#   it BLOCKS the stop and injects them, so the session handles them instead of going quiet.
#
# Scope: acts ONLY in an ultraloop TEAM session — TEAM_NAME set AND an ultraloop config is present. That covers BOTH
#   crew (lanes/main) and multi-repo (workers/meta), which both set TEAM_NAME; a non-team or non-ultraloop session no-ops.
# Messages are POINTERS (the board is the SoT), so a drained-but-unseen message is recoverable from the board next turn.
#
# ★ Safety (mandatory — same invariant as goal-stop-gate.sh): unguarded Stop re-injection runs away. So ALWAYS FAIL-OPEN:
#   any error / uncertainty → allow stop (exit 0, no output). No recursion (reads cc-hub only; never spawns claude/tmux).
#   Termination: the hook CONSUMES on read, so once the inbox drains the next stop is allowed — it can only keep a
#   session alive while new messages actually keep arriving (bounded by the sender; /goal + dead-man cap the session overall).
#
# Install: hooks.Stop in hooks/hooks.json (plugin-level). Invocation: bash "${CLAUDE_PLUGIN_ROOT}/hooks/stop-inbox-check.sh".
# Output: on messages → {"decision":"block","reason":"..."} on stdout · otherwise exit 0 (allow stop).
set -uo pipefail

# fast path: not a team session → allow stop
[ -n "${TEAM_NAME:-}" ] || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HOOK_DIR/.." && pwd)"
# shellcheck source=/dev/null
. "$SKILL_DIR/scripts/_lib.sh" 2>/dev/null || exit 0    # no lib → allow stop

# ultraloop team session only → else allow stop. TEAM_NAME (above) is set by both crew (ows wt-spawn) and multi-repo
#   (worker_spawn); requiring an ultraloop config here scopes the block to ultraloop sessions (a non-ultraloop team
#   session with the plugin globally enabled must not have its stop blocked by us).
[ -f "$(ue_config_path 2>/dev/null)" ] || exit 0

CCHUB="${TCTL_CCHUB_BASE:-http://127.0.0.1:28797}"
resp="$(curl -fsS -m 3 "$CCHUB/team/inbox/$TEAM_NAME?consume=true&limit=20" 2>/dev/null)" || exit 0
[ -n "$resp" ] || exit 0

count="$(printf '%s' "$resp" | jq -r '.count // 0' 2>/dev/null)" || exit 0
case "$count" in ''|*[!0-9]*) exit 0;; esac
[ "$count" -gt 0 ] || exit 0

msgs="$(printf '%s' "$resp" | jq -r '.messages[]? | "- **\(.from)**: \(.body)"' 2>/dev/null)"
[ -n "$msgs" ] || exit 0

reason="📬 ${count} new team message(s) arrived before this stop — handle them first (they point at the board = the source of truth), then you may stop once the inbox is empty:
${msgs}"

# block the stop and feed the messages back to the model (JSON-escape via python, like goal-stop-gate.sh)
printf '{"decision":"block","reason":%s}\n' \
  "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$reason" 2>/dev/null || printf '"team messages pending"')"
exit 0
