#!/usr/bin/env bash
# e2e_run.sh <issue#> [scenario] — 실제 구동 시나리오 + 캡쳐 증거.
#   exit 0 = PASS · 1 = 결정적 FAIL
# flake 처리(REQ-E2E-6): 일시 실패(포트/타임아웃/워밍업)는 백오프 재시도(≤flake_retries),
#   재시도 후에도 실패해야 결정적 FAIL. flake는 strike 아님.
#
# ★ 이 스크립트는 *프레임*만 잡는다. 실제 클릭/셸/HTTP 시나리오와 결정적 assertion은 에이전트가
#   브라우저 MCP / 별도 셸 세션으로 수행하고, 그 결과를 e2e/reports/<date>-<item>.md 에 캡쳐한다.
#   (assets/e2e/scenario.template.md · report.template.md)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true
ISSUE="${1:?issue#}"; SCN="${2:-default}"
RETRIES="$(cfg_get e2e.flake_retries 3)"; MAXMB="$(cfg_get e2e.screenshot_max_mb 2)"
REPORT_DIR="./e2e/reports"; mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/$(date +%Y%m%d)-issue${ISSUE}.md"

echo "[e2e run] issue=$ISSUE scenario=$SCN retries=$RETRIES report=$REPORT"
echo "  · 에이전트 할 일: 시나리오 실행(웹=브라우저MCP 클릭+스크린샷 / CLI=별도 셸 / API=실HTTP)"
echo "  · 결정적 assertion 병행(HTTP status·DB 행수·파일 존재·exit code)"
echo "  · 스크린샷 압축<${MAXMB}MB → 링크/썸네일로 리포트에 (원본 임베드 금지, DLP)"

# 자동 신호로 잡을 수 있는 부분: 스택이 살아있나(포트), 시나리오 스크립트 파일이 있으면 실행.
# 일시 실패는 재시도. (실제 PASS/FAIL 최종 판정은 에이전트가 리포트에 기록 후 이 스크립트의 종료코드로 반영)
SCN_FILE="./e2e/scenarios/${SCN}.sh"
attempt=0
while :; do
  attempt=$((attempt+1))
  if [ -x "$SCN_FILE" ]; then
    if bash "$SCN_FILE"; then RC=0; else RC=$?; fi
  else
    # 시나리오 스크립트가 없으면, 에이전트가 인터랙티브로 수행했다고 보고 리포트의 최종결과 마커로 판정.
    # report.template "## 최종 결과"의 **PASS**/**FAIL** 마커만 본다 — 'password'/'bypass' 부분일치나
    # 스텝표의 'PASS/FAIL' 안내문 오탐 방지. 둘 다 없으면(미작성) FAIL 취급.
    if grep -qE '\*\*PASS\*\*' "$REPORT" 2>/dev/null && ! grep -qE '\*\*FAIL\*\*' "$REPORT" 2>/dev/null; then RC=0; else RC=1; fi
  fi
  if [ "$RC" -eq 0 ]; then echo "  ✓ E2E PASS (attempt $attempt)"; exit 0; fi
  # 일시 실패 신호면 백오프 재시도
  if [ "$attempt" -lt "$RETRIES" ]; then
    ue_log "E2E 실패(일시 가능) attempt=$attempt → 백오프 재시도"; sleep $((attempt*3)); continue
  fi
  ue_log "E2E 결정적 FAIL (재시도 $RETRIES 소진) → e2e:fail + bug 이슈로"
  exit 1
done
