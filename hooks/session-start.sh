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
