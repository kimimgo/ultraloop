#!/usr/bin/env bash
# ultraloop compose_msg.sh — 커밋/PR/알림용 한국어 메시지 BODY 작성기
# SPEC §11 REQ-MSG-1: TITLE 은 결정적 `type(scope): subject` 템플릿(체인지로그/semver/
#   보드자동화 안정성)으로 고정하고, BODY(왜/무엇)만 LLM 한국어로 채운다.
#
# 사용법: compose_msg.sh <kind> <context...>
#   kind ∈ commit | pr | notify
#
# 동작: 한국어 윤문 스킬(humanize-korean / stop-slop)이 깔려 있으면 BODY 를 그쪽으로
#   라우팅하라는 힌트를 출력하고, 없으면 인라인 plain-Korean BODY 스켈레톤을 출력한다.
#   실제 BODY 채우기는 에이전트가 한다 — 이 스크립트는 가이드 + 골격만 stdout 으로 낸다.
set -uo pipefail

KIND="${1:-commit}"; shift || true
CONTEXT="$*"

SKILLS_DIR="${HOME}/.claude/skills"
KO_SKILL=""
if [ -d "${SKILLS_DIR}/humanize-korean" ]; then
  KO_SKILL="humanize-korean"
elif [ -d "${SKILLS_DIR}/stop-slop" ]; then
  KO_SKILL="stop-slop"
fi

echo "# ── ultraloop compose_msg (${KIND}) ──"
echo "# context: ${CONTEXT:-<none>}"
echo "#"
echo "# [TITLE — 결정적, 직접 채움 / LLM 금지]"
echo "#   형식: type(scope): subject"
echo "#   type ∈ feat|fix|refactor|docs|test|chore|perf|build|ci"
echo "#"

if [ -n "$KO_SKILL" ]; then
  echo "# [BODY — 한국어 윤문 스킬로 라우팅]"
  echo "#   감지됨: ${KO_SKILL}  →  아래 초안 BODY 를 '${KO_SKILL}' 스킬로 다듬어라."
  echo "#   (왜/무엇 중심, AI 티 제거된 자연스러운 한국어로)"
else
  echo "# [BODY — 인라인 plain-Korean (윤문 스킬 없음)]"
  echo "#   아래 골격을 사람이 쓴 듯 간결한 한국어로 직접 채운다."
fi

echo ""
case "$KIND" in
  pr)
    echo "## 무엇을"
    echo "- (이 PR이 바꾸는 것 한 줄)"
    echo ""
    echo "## 왜"
    echo "- (배경/문제와 이 변경이 필요한 이유)"
    echo ""
    echo "## 검증"
    echo "- (어떻게 확인했는지: 테스트/실행 근거)"
    ;;
  notify)
    echo "(상황 한 줄 요약 — 무엇이 일어났고 다음 행동은 무엇인지)"
    ;;
  commit|*)
    echo "(왜 이 변경이 필요한지 1~3줄)"
    echo ""
    echo "(무엇을 어떻게 바꿨는지 핵심만)"
    ;;
esac
