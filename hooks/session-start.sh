#!/usr/bin/env bash
# ultraloop SessionStart hook — if cwd is an ultraloop project, surface one "active + progress" line at session start.
#   No graphql calls (reads only the status.json cache — avoids session-start delay). Non-project: exits quietly (no output).
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Walk upward from cwd to root — ultraloop project detection (config or bootstrap marker).
d="$PWD"; cfg=""
while [ -n "$d" ] && [ "$d" != "/" ]; do
  [ -f "$d/ultraloop.config.yaml" ] && { cfg="$d"; break; }
  [ -f "$d/.claude/.ultraloop-bootstrapped" ] && { cfg="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$cfg" ] && exit 0   # not an ultraloop project — stay quiet

LINE="$(bash "$SDIR/../scripts/status.sh" --line 2>/dev/null)"
printf '🔁 ultraloop active project — %s\n' "${LINE:-(board not yet tallied)}"

# Project-context brief — the local mirror of the board README (SoT). Cache-only (no graphql → no session-start delay):
#   linked repos / collaborators / special project rules, so a fresh session knows the context immediately.
#   Refreshed from the board by the loop (best-effort) or by hand: gh-roadmap roadmap_readme.sh cache.
CTX="$cfg/.claude/.ultraloop-context.md"
if [ -s "$CTX" ]; then
  printf '\n📌 project context (board README mirror) —\n'
  sed -e '/^<!--/,/-->/d' -e '/^[[:space:]]*$/d' "$CTX" 2>/dev/null | head -40
fi

# Advisory config doctor — surface the one-line health verdict. Never hard-fail the
# SessionStart hook: config_check.sh exits non-zero on a missing REQUIRED item, so its
# exit code is deliberately ignored here (advisory only).
DOCTOR="$(bash "$SDIR/../scripts/config_check.sh" 2>/dev/null | tail -1 || true)"
[ -n "$DOCTOR" ] && printf '\n🩺 %s\n' "$DOCTOR"
