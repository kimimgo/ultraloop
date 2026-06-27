#!/usr/bin/env bash
# ultraloop SessionStart hook — cwd 가 ultraloop 프로젝트면 '활성 + 진척도' 한 줄을 세션 시작 시 노출.
#   graphql 호출 안 함(status.json 캐시만 읽음 — 세션 시작 지연 방지). 비-프로젝트면 조용히 종료(출력 없음).
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# cwd 부터 루트까지 상향 탐색 — ultraloop 프로젝트 판정(config 또는 부트스트랩 마커).
d="$PWD"; cfg=""
while [ -n "$d" ] && [ "$d" != "/" ]; do
  [ -f "$d/ultraloop.config.yaml" ] && { cfg="$d"; break; }
  [ -f "$d/.claude/.ultraloop-bootstrapped" ] && { cfg="$d"; break; }
  d="$(dirname "$d")"
done
[ -z "$cfg" ] && exit 0   # ultraloop 프로젝트 아님 — 조용히

LINE="$(bash "$SDIR/../scripts/status.sh" --line 2>/dev/null)"
printf '🔁 ultraloop 활성 프로젝트 — %s\n' "${LINE:-(보드 미집계)}"
