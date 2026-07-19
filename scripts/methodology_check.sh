#!/usr/bin/env bash
# methodology_check.sh [<branch>] [--base <ref>] [--red <sha>] [--green <sha>]
#   The deterministic leg of the v0.16 methodology barrier: a lane subagent's Skill-tool calls
#   cannot be read downstream, but the artifact TDD leaves behind — commit ordering — can.
#   This verifies that on the lane branch a failing-test (test:*) commit precedes the
#   implementation (feat:/fix:*) commit that makes it pass. A fabricated methodology object
#   in a lane's structured return cannot fake the commit graph.
#
#   Modes (config methodology.tdd_evidence): enforce (default) | warn | off.
#     exit 0 = pass / not-applicable (docs-only, or mode=off)
#     exit 1 = environment/usage error (loud — base unresolvable, bad flag, no git)
#     exit 5 = TDD commit-ordering violation
#     exit 6 = methodology evidence missing/contradicted (--red/--green cross-check failed)
#   In warn mode every check still runs and prints, but the script always exits 0 with a WARN line.
#   Last line is greppable: `methodology-check: PASS|WARN|FAIL — <reason>`.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

command -v git >/dev/null 2>&1 || { echo "methodology-check: FAIL — git not found"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "methodology-check: FAIL — not a git repository"; exit 1; }

# tdd_evidence: enforce|warn|off. NOTE: YAML 1.1 coerces a bare `off`/`no` to boolean false (cfg_get
# then yields "false"), so accept those spellings as off too — a user writing `tdd_evidence: off` means off.
MODE="$(cfg_get methodology.tdd_evidence enforce)"
case "$MODE" in
  off|false|no)     MODE=off ;;
  warn)             MODE=warn ;;
  enforce|true|yes) MODE=enforce ;;
  *)                MODE=enforce ;;
esac
if [ "$MODE" = "off" ]; then
  echo "methodology-check: PASS — tdd_evidence=off (deterministic gate disabled by config)"; exit 0
fi

# ── argument parsing ─────────────────────────────────────────────────────────
BRANCH=""; BASE_ARG=""; RED=""; GREEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base)  BASE_ARG="${2:-}"; shift 2 ;;
    --red)   RED="${2:-}";      shift 2 ;;
    --green) GREEN="${2:-}";    shift 2 ;;
    --*)     echo "methodology-check: FAIL — unknown flag $1"; exit 1 ;;
    *)       [ -z "$BRANCH" ] && BRANCH="$1"; shift ;;
  esac
done
[ -n "$BRANCH" ] || BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || { echo "methodology-check: FAIL — branch/ref '$BRANCH' does not resolve"; exit 1; }

DEFB="$(cfg_get default_branch main)"
if [ -n "$BASE_ARG" ]; then
  BASE="$(git rev-parse --verify "$BASE_ARG" 2>/dev/null)" || { echo "methodology-check: FAIL — --base '$BASE_ARG' does not resolve"; exit 1; }
else
  BASE="$(git merge-base "$BRANCH" "origin/$DEFB" 2>/dev/null)" \
    || BASE="$(git merge-base "$BRANCH" "$DEFB" 2>/dev/null)" \
    || BASE=""
fi
[ -n "$BASE" ] || { echo "methodology-check: FAIL — cannot resolve base (tried origin/$DEFB and $DEFB); pass --base <ref>"; exit 1; }

# ── gather commits + changed files on BASE..BRANCH (branch-unique work) ───────
US=$'\x1f'
mapfile -t COMMITS < <(git log --reverse --no-merges --format="%H${US}%s" "$BASE..$BRANCH" 2>/dev/null)
mapfile -t FILES   < <(git diff --name-only "$BASE..$BRANCH" 2>/dev/null)

classify() {  # subject → TEST | IMPL | NEUTRAL (deterministic per messaging.md commit template)
  case "$1" in
    *) if   [[ "$1" =~ ^test[\(:] ]];        then echo TEST
       elif [[ "$1" =~ ^(feat|fix)[\(:] ]];  then echo IMPL
       else echo NEUTRAL; fi ;;
  esac
}
is_doc() { case "$1" in docs/*|e2e/reports/*|*.md) return 0 ;; *) return 1 ;; esac; }

print_table() {
  echo "  branch=$BRANCH base=${BASE:0:12} commits=${#COMMITS[@]} files=${#FILES[@]} mode=$MODE"
  local line h s
  for line in "${COMMITS[@]}"; do
    h="${line%%${US}*}"; s="${line#*${US}}"
    printf '    %-7s %s  %s\n' "$(classify "$s")" "${h:0:9}" "$s"
  done
}
verdict() {  # $1=code $2=reason — honors MODE, prints table + greppable last line
  local code="$1" reason="$2"
  print_table
  if [ "$code" = "0" ]; then echo "methodology-check: PASS — $reason"; exit 0; fi
  if [ "$MODE" = "warn" ]; then echo "methodology-check: WARN — $reason (tdd_evidence=warn — not blocking)"; exit 0; fi
  echo "methodology-check: FAIL — $reason"; exit "$code"
}

# ── C1: empty branch (before the docs-only N.A. shortcut, so empty ≠ not-applicable) ──
[ "${#COMMITS[@]}" -gt 0 ] || verdict 5 "empty branch — no commits ahead of base; a lane cannot claim work done"

# ── docs-only → not applicable ────────────────────────────────────────────────
srcchanged=0
for f in "${FILES[@]}"; do is_doc "$f" || { srcchanged=1; break; }; done
if [ "${#FILES[@]}" -gt 0 ] && [ "$srcchanged" -eq 0 ]; then
  verdict 0 "docs-only change — TDD evidence not applicable"
fi

# ── classify commit stream ────────────────────────────────────────────────────
nTest=0; nImpl=0; firstTest=-1; firstImpl=-1; idx=0
for line in "${COMMITS[@]}"; do
  c="$(classify "${line#*${US}}")"
  case "$c" in
    TEST) nTest=$((nTest+1)); [ "$firstTest" -lt 0 ] && firstTest=$idx ;;
    IMPL) nImpl=$((nImpl+1)); [ "$firstImpl" -lt 0 ] && firstImpl=$idx ;;
  esac
  idx=$((idx+1))
done

# ── C2: implementation with no test ───────────────────────────────────────────
[ "$nImpl" -gt 0 ] && [ "$nTest" -eq 0 ] \
  && verdict 5 "implementation commit(s) present but no test:* commit — write the failing test first"
# ── C3: implementation precedes its test (test-first order) ───────────────────
[ "$nImpl" -gt 0 ] && [ "$nTest" -gt 0 ] && [ "$firstImpl" -lt "$firstTest" ] \
  && verdict 5 "first implementation commit precedes the first test:* commit — test-first order violated"
# ── C4: source changed but no classified commits (prefix-evasion guard) ───────
[ "$srcchanged" -eq 1 ] && [ "$((nTest+nImpl))" -eq 0 ] \
  && verdict 5 "source files changed but no test:*/feat:*/fix:* commits — methodology evidence missing (commit-prefix evasion)"

# ── C5: optional --red/--green cross-examination (from a lane's evidence object) ──
if [ -n "$RED" ] || [ -n "$GREEN" ]; then
  { [ -n "$RED" ] && [ -n "$GREEN" ]; } || verdict 6 "methodology evidence incomplete — need both --red and --green"
  git merge-base --is-ancestor "$RED"   "$BRANCH" 2>/dev/null || verdict 6 "red commit $RED is not on branch $BRANCH"
  git merge-base --is-ancestor "$GREEN" "$BRANCH" 2>/dev/null || verdict 6 "green commit $GREEN is not on branch $BRANCH"
  rsub="$(git log -1 --format='%s' "$RED" 2>/dev/null)"
  [ "$(classify "$rsub")" = "TEST" ] || verdict 6 "red commit $RED is not a test:* commit (subject: $rsub)"
  git merge-base --is-ancestor "$RED" "$GREEN" 2>/dev/null || verdict 6 "red commit is not an ancestor of green — the failing test must precede its implementation"
fi

verdict 0 "test-first order verified ($nTest test-commit(s) precede $nImpl implementation commit(s))"
