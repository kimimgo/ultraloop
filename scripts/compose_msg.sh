#!/usr/bin/env bash
# ultraloop compose_msg.sh — message BODY composer for commits/PRs/notifications
# SPEC §11 REQ-MSG-1: TITLE is fixed to the deterministic `type(scope): subject` template
#   (changelog/semver/board-automation stability); only the BODY (why/what) is filled by the
#   LLM in the product working language.
#
# usage: compose_msg.sh <kind> <context...>
#   kind ∈ commit | pr | notify
#
# behavior: if a Korean prose-refinement skill (humanize-korean / stop-slop) is installed,
#   print a hint to route the BODY through it; otherwise print an inline plain-language BODY skeleton.
#   The agent fills the actual BODY — this script only emits guidance + skeleton to stdout.
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
echo "# [TITLE — deterministic, filled directly / no LLM]"
echo "#   format: type(scope): subject"
echo "#   type ∈ feat|fix|refactor|docs|test|chore|perf|build|ci"
echo "#"

if [ -n "$KO_SKILL" ]; then
  echo "# [BODY — route through the prose-refinement skill]"
  echo "#   detected: ${KO_SKILL}  →  polish the draft BODY below with the ${KO_SKILL} skill."
  echo "#   (why/what focused, natural prose in the product working language, no AI tells)"
else
  echo "# [BODY — inline plain prose (no refinement skill)]"
  echo "#   Fill the skeleton below directly, concise and human, in the product working language."
fi

echo ""
case "$KIND" in
  pr)
    echo "## What"
    echo "- (one line: what this PR changes)"
    echo ""
    echo "## Why"
    echo "- (background/problem and why this change is needed)"
    echo ""
    echo "## Verification"
    echo "- (how it was checked: tests/run evidence)"
    ;;
  notify)
    echo "(one-line status summary — what happened and what the next action is)"
    ;;
  commit|*)
    echo "(1-3 lines on why this change is needed)"
    echo ""
    echo "(only the essentials of what changes and how)"
    ;;
esac
