#!/usr/bin/env bash
# bootstrap_repo.sh — one-time initial repo setup (idempotent). Passes through if already done.
# What it does: prerequisite probe → labels → board (idempotent query-then-create) → templates/workflows →
#          main protection (review=0) → Environments (staging auto / production HITL) →
#          goal Stop hook install (absolute-path substitution) → CLAUDE.md/PROGRESS.md seed → initial commit.
# Non-deterministic: Projects v2 board/Environments depend on permissions and plan, so *attempt, and on failure report clearly and point to the fallback*.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SDIR/.." && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
echo "== ultraloop bootstrap =="; echo "repo=$REPO branch=$DEFB"

# 0) Seed the config on first run (idempotent — README quickstart promises this).
#    Without a config every cfg_get falls back to defaults silently; seeding makes the
#    knobs visible and marks the repo as an ultraloop project for the SessionStart hook.
if [ ! -f "./ultraloop.config.yaml" ] && [ -f "$SKILL_DIR/config.example.yaml" ]; then
  cp "$SKILL_DIR/config.example.yaml" ./ultraloop.config.yaml \
    && echo "  ✓ seeded ultraloop.config.yaml from the example — edit repo: and mission (defaults are safe)" \
    || echo "  · config seed failed (copy by hand: $SKILL_DIR/config.example.yaml)"
fi

# ── 0. prerequisite probe (warn clearly when missing; silent degrade forbidden) ─────
probe() { command -v "$1" >/dev/null 2>&1 && echo "  ✓ $1" || echo "  ✗ $1  ($2)"; }
echo "[probe]"
probe git    "required";  probe gh "required"
probe docker "E2E: fallback = launch via a single README command"
probe python3 "recommended for config/board parsing"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
[ -n "${!TOKEN_ENV:-${GH_TOKEN:-}}" ] && echo "  ✓ project-scope token($TOKEN_ENV)" || echo "  ✗ project-scope token  (no Projects v2 automation → fallback Milestone+labels, roadmap-model §6)"
DTOKEN_ENV="$(cfg_get discord.token_env ULTRALOOP_DISCORD_BOT_TOKEN)"
[ -n "${!DTOKEN_ENV:-}" ] && echo "  ✓ discord token($DTOKEN_ENV)" || echo "  · discord token missing  (notifications fall back to console; approvals = result file, notify-approval.md)"
echo "  · browser MCP availability is probed by the agent in the first loop ① and recorded in the PROGRESS view"

# ── 0.1 dependency skill probe (references/dependencies.md) — gh-roadmap=board authority (required), rest=fallback possible ──
echo "[skills]"
GHR_DIR=""
# Priority: local user copy (live dev copy) → plugin bundle (v0.8.0+, always present) → marketplace cache.
for d in "$HOME/.claude/skills/gh-roadmap" "$SKILL_DIR/skills/gh-roadmap" \
         "$HOME"/.claude/plugins/*/skills/gh-roadmap "$HOME"/.claude/plugins/cache/*/*/skills/gh-roadmap; do
  [ -f "$d/SKILL.md" ] && { GHR_DIR="$d"; break; }
done
[ -n "$GHR_DIR" ] && echo "  ✓ gh-roadmap (board structure/setup authority): $GHR_DIR" \
  || echo "  ✗ gh-roadmap missing (bundle damaged?) — board views, roadmap, built-in workflow automation unavailable (references/dependencies.md)."
for s in product-strategy outcome-roadmap strategy-red-team prioritization-frameworks tdd-workflow; do
  [ -d "$HOME/.claude/skills/$s" ] && echo "  ✓ $s" || echo "  · $s missing (fallback: ultraloop performs it directly)"
done
# gstack lane (entirely optional — references/dependencies.md §4). When absent: ONE summary
# line, not a wall of ✗ (a missing optional lane must not read as a broken product).
GSTACK_HOME_DIR=""
for d in "$HOME/.claude/skills/gstack" "$HOME"/.claude/plugins/*/skills/gstack; do
  [ -d "$d" ] && { GSTACK_HOME_DIR="$d"; break; }
done
if [ -n "$GSTACK_HOME_DIR" ]; then
  GS_HAVE=0; GS_MISS=""
  for s in office-hours autoplan spec investigate qa-only review ship land-and-deploy canary health retro; do
    if [ -e "$GSTACK_HOME_DIR/$s" ] || [ -e "$GSTACK_HOME_DIR/${s}/SKILL.md" ]; then GS_HAVE=$((GS_HAVE+1)); else GS_MISS="$GS_MISS $s"; fi
  done
  echo "  ✓ gstack lane: $GS_HAVE/11 entries available ($GSTACK_HOME_DIR)${GS_MISS:+ — missing:$GS_MISS}"
else
  echo "  · gstack lane: not installed — optional, every step falls back (dependencies.md §4)"
fi

[ -n "$REPO" ] || { echo "✗ repo not resolved — set config.repo or pass the slash argument (/ultraloop owner/name)"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "✗ gh required"; exit 1; }

# ── 0.5 create repo when absent (new project, §4.1.1) ───────────────────────────
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  VIS="$(cfg_get repo_visibility private)"
  echo "[repo create] $REPO does not exist → gh repo create --$VIS"
  if gh repo create "$REPO" "--$VIS" -d "ultraloop project" >/dev/null 2>&1; then
    echo "  ✓ created ($VIS)"
    git rev-parse --git-dir >/dev/null 2>&1 || git init -q
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git" 2>/dev/null || true
  else
    echo "  ✗ creation failed (permission or duplicate name?) — run gh repo create $REPO manually, then re-run"; exit 1
  fi
fi

# ── 1. labels (idempotent) ───────────────────────────────────────────────────
echo "[labels]"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys;[print(l["name"],l["color"],l.get("description","")) for l in json.load(open(sys.argv[1]))]' \
    "$SKILL_DIR/assets/labels.json" 2>/dev/null | while read -r name color desc; do
    gh label create "$name" --color "$color" --description "$desc" -R "$REPO" 2>/dev/null \
      || gh label edit "$name" --color "$color" --description "$desc" -R "$REPO" 2>/dev/null || true
  done
  echo "  ✓ labels synced"
else
  echo "  · python3 missing — labels must be created manually (assets/labels.json)"
fi

# ── 2. board (Projects v2) — delegated to gh-roadmap (board structure/setup authority) · golden template copy ──
#  ⚠️ Views, Roadmap layout, and built-in workflows cannot be created via API (verified) → copyProjectV2 (golden template) is the only automation.
echo "[board → gh-roadmap]"
PNODE="$(cfg_get roadmap.project_node_id "")"
TEMPLATE="$(cfg_get roadmap.template_node_id "")"
if [ -n "$PNODE" ]; then
  echo "  ✓ project_node_id already recorded (idempotent pass): $PNODE"
elif [ -n "$GHR_DIR" ]; then
  echo "  · board structure/setup = gh-roadmap authority (references/dependencies.md). Set up next:"
  echo "    1) cp $GHR_DIR/config.example.yaml ./gh-roadmap.config.yaml"
  echo "       → set board.owner=${REPO%%/*} · board.title · repos:[{name:$REPO}]"
  if [ -n "$TEMPLATE" ]; then
    echo "       → board.template_node_id=$TEMPLATE  (★ golden template → copyProjectV2 replicates 3 views, roadmap, built-in workflows)"
  else
    echo "       ⚠️ template_node_id empty → fresh board (no roadmap view or built-in workflows)."
    echo "          Recommended: build the golden template once via golden-template-setup.md, then record its id in roadmap.template_node_id."
  fi
  echo "    2) bash $GHR_DIR/scripts/roadmap_bootstrap.sh   # board copy/create + N-repo link + fields (Horizon·Target Date)"
  echo "    3) bash $GHR_DIR/scripts/roadmap_view.sh check  # verify views (ROADMAP_LAYOUT), built-in workflows (enabled), fields"
  echo "    4) record the created project_node_id/number in ultraloop.config.yaml (roadmap.*) (idempotency key)"
else
  echo "  ✗ gh-roadmap missing (★ required dependency) — fallback: create board/fields directly via roadmap-model.md §4 query-then-create"
  echo "    (assets/project-fields.json: includes Status·Priority·Horizon·Target Date·E2E-Evidence)."
  echo "    ⚠️ roadmap layout views and built-in workflows need the golden template (no API creation) — installing gh-roadmap recommended."
fi

# ── 2.5 project-context mirror ← board README (SoT). Best-effort — pulls only when the board already exists (BP#context). ──
if [ -n "$PNODE" ] && [ -n "$GHR_DIR" ] && [ -f "$GHR_DIR/scripts/roadmap_readme.sh" ]; then
  echo "[context ← board README]"
  CTX_MSG="$(bash "$GHR_DIR/scripts/roadmap_readme.sh" cache .claude/.ultraloop-context.md --pnode "$PNODE" 2>/dev/null)"
  [ -n "$CTX_MSG" ] && echo "  ✓ context mirror refreshed from the board README (SessionStart injects it)" \
    || echo "  · board README empty — the seeded scaffold stands (fill .claude/.ultraloop-context.md, then roadmap_readme.sh set)"
fi

# ── 3. copy templates/workflows ─────────────────────────────────────────────
echo "[templates]"
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
cp -n "$SKILL_DIR/assets/workflows/"*.yml .github/workflows/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/issue_templates/"*.md .github/ISSUE_TEMPLATE/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/pr_template.md" .github/pull_request_template.md 2>/dev/null || true
# auto-add workflow — gh-roadmap fills the one built-in workflow gap (auto-add) that the golden template cannot replicate.
[ -n "${GHR_DIR:-}" ] && [ -f "$GHR_DIR/assets/add-to-project.yml" ] && \
  cp -n "$GHR_DIR/assets/add-to-project.yml" .github/workflows/add-to-project.yml 2>/dev/null && \
  echo "  · auto-add.yml copied (PROJECT_URL and ADD_TO_PROJECT_PAT secrets must be substituted — golden-template-setup §C)" || true
[ -f PROGRESS.md ] || cp "$SKILL_DIR/assets/PROGRESS.template.md" PROGRESS.md 2>/dev/null || true
[ -f CLAUDE.md ]   || cp "$SKILL_DIR/assets/CLAUDE.template.md" CLAUDE.md 2>/dev/null || true
# Project-context mirror — a fillable scaffold so a fresh SessionStart has something to show; the board README is the SoT (§2.5 pulls it).
[ -f .claude/.ultraloop-context.md ] || { mkdir -p .claude; cp "$SKILL_DIR/assets/CONTEXT.template.md" .claude/.ultraloop-context.md 2>/dev/null && echo "  · seeded .claude/.ultraloop-context.md (fill it: repos, collaborators, project rules → publish with gh-roadmap roadmap_readme.sh set)"; }
# specs/ placeholder (Spec Kit spec originals, §4.1.3). specify init is run by the agent at the gate — bootstrap only makes the spot.
mkdir -p "$(cfg_get spec.specs_dir specs)" 2>/dev/null && : > "$(cfg_get spec.specs_dir specs)/.gitkeep" 2>/dev/null || true
echo "  ✓ workflows/issue/pr/PROGRESS/CLAUDE/specs seeded (only when absent)"
echo "  · the agent adapts CI workflow lint/test/build to the stack (references/rules/*)"

# ── 3.5 ★ self-hosted runner check (enforced principle, ci-cd-hitl.md §0) ─────
echo "[self-hosted runner]"
RUNNERS_ONLINE="$(gh api "repos/$REPO/actions/runners" --jq '[.runners[]|select(.status=="online")]|length' 2>/dev/null || echo "?")"
if [ "$RUNNERS_ONLINE" = "?" ]; then
  echo "  · runner query failed (permission?) — the agent must re-verify before waiting on CI (ci-cd-hitl.md §0)"
elif [ "$RUNNERS_ONLINE" -ge 1 ] 2>/dev/null; then
  echo "  ✓ online self-hosted runner: $RUNNERS_ONLINE"
else
  echo "  ✗ no self-hosted runner — every workflow uses runs-on: self-hosted, so CI stays queued forever."
  echo "    → register a self-hosted runner: https://docs.github.com/en/actions/hosting-your-own-runners (idempotent setup, ci-cd-hitl.md §0)"
  echo "    If installation is impossible (sudo or another host required), do not proceed with the loop + notify (notify-approval.md)."
fi
# Drift correction for existing workflows: force-replace GitHub-hosted runners with self-hosted when found.
if grep -rln 'runs-on:.*\(ubuntu\|macos\|windows\)-' .github/workflows/ >/dev/null 2>&1; then
  sed -i 's/runs-on:[[:space:]]*\(ubuntu\|macos\|windows\)-[a-z0-9.-]*/runs-on: self-hosted   # ★ forced correction: self-hosted principle (ci-cd-hitl.md §0)/' .github/workflows/*.yml 2>/dev/null || true
  echo "  ✓ GitHub-hosted runs-on found → corrected to self-hosted"
fi

# ── 4. main protection (review=0 = unattended auto-merge, bot bypass) ────────────────
echo "[branch protection]"
gh api -X PUT "repos/$REPO/branches/$DEFB/protection" -H "Accept: application/vnd.github+json" \
  -f 'required_status_checks[strict]=true' -F 'required_status_checks[contexts][]=' \
  -F 'enforce_admins=false' \
  -f 'required_pull_request_reviews[required_approving_review_count]=0' \
  -F 'restrictions=' -F 'allow_force_pushes=false' -F 'allow_deletions=false' \
  >/dev/null 2>&1 && echo "  ✓ protected (review=0)" || echo "  · protection setup failed (plan/permission) — record in the PROGRESS view and continue"

# ── 5. Environments (staging auto / production HITL) ─────────────────────────
echo "[environments]"
gh api -X PUT "repos/$REPO/environments/staging" >/dev/null 2>&1 && echo "  ✓ staging" || echo "  · staging env failed (plan)"
REV="$(cfg_get hitl.reviewers '[]')"
ENVN="$(cfg_get hitl.gated_environment production)"
echo "  · production env = required reviewers (HITL). reviewers=$REV"
echo "    (format: [{\"type\":\"User|Team\",\"id\":<numeric id>}] — not a username. Under personal-repo/plan limits, fall back to manual cd.yml approval — ci-cd-hitl.md)"
if [ -n "$REV" ] && [ "$REV" != "[]" ]; then
  # Actually register the reviewer payload — a PUT of the environment alone does not enforce HITL approval.
  printf '{"reviewers":%s}' "$REV" | gh api -X PUT "repos/$REPO/environments/$ENVN" --input - >/dev/null 2>&1 \
    && echo "  ✓ production env + required reviewers registered" \
    || echo "  · reviewer registration failed (id format/plan) — falling back to manual cd.yml approval"
else
  gh api -X PUT "repos/$REPO/environments/$ENVN" >/dev/null 2>&1 \
    && echo "  · production env created (no reviewer — hitl.reviewers empty; manual cd.yml approval fallback)" || true
fi

# ── 6. goal Stop hook install (.claude/settings.json, absolute-path substitution) ─────
echo "[goal stop-hook]"
if [ "$(cfg_get engine.goal.install_stop_hook true)" = "true" ]; then
  mkdir -p .claude
  SNIP="$(sed "s#__ULTRALOOP_SKILL_DIR__#$SKILL_DIR#g" "$SKILL_DIR/assets/hooks/settings.snippet.json")"
  if [ -f .claude/settings.json ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$SKILL_DIR" <<'PY' 2>/dev/null && echo "  ✓ Stop hook merged" || echo "  · settings.json merge failed — manual addition needed"
import json,sys,os
skill=sys.argv[1]
p=".claude/settings.json"
d=json.load(open(p))
d.setdefault("hooks",{}).setdefault("Stop",[])
cmd=f"bash {skill}/assets/hooks/goal-stop-gate.sh"
if not any(cmd in json.dumps(x) for x in d["hooks"]["Stop"]):
    d["hooks"]["Stop"].append({"hooks":[{"type":"command","command":cmd}]})
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
  else
    printf '%s\n' "$SNIP" > .claude/settings.json && echo "  ✓ Stop hook installed (.claude/settings.json)"
  fi
  echo "  · guards always ON: max_iterations/lock/budget/dead-man (engine-loop-and-goal §3)"
else
  echo "  · goal.install_stop_hook=false — gate not installed (prompt loop only)"
fi

# ── 6.5 ★ worktree optimization (.claude/settings.json worktree.baseRef) ─────
# Parallel lanes run isolated via isolation:"worktree". Pinning where a lane branches from
# secures reproducibility and keeps unpushed local work from leaking into lanes (worktree-strategy.md §0).
echo "[worktree baseRef]"
BASEREF="$(cfg_get worktree.base_ref fresh)"
case "$BASEREF" in fresh|head) ;; *) echo "  · unknown base_ref=$BASEREF → corrected to fresh"; BASEREF=fresh ;; esac
mkdir -p .claude
if command -v python3 >/dev/null 2>&1; then
  python3 - "$BASEREF" <<'PY' 2>/dev/null && echo "  ✓ worktree.baseRef=$BASEREF recorded (.claude/settings.json)" || echo "  · settings.json merge failed — manual: \"worktree\":{\"baseRef\":\"$BASEREF\"}"
import json,sys,os
ref=sys.argv[1]; p=".claude/settings.json"
d=json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d.setdefault("worktree",{})["baseRef"]=ref
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
else
  echo "  · python3 missing — manually add \"worktree\":{\"baseRef\":\"$BASEREF\"} to .claude/settings.json"
fi
echo "  · fresh=branch lanes from origin/<default> (recommended) | head=on top of unpushed local commits (worktree-strategy.md §0)"

# ── 6.6 ★ Dynamic-workflow casting defaults (.claude/settings.json, references/dynamic-workflow-design.md §2) ──
#  Records the casting policy (model×effort per stage type) as a hint for Workflow-stage subagents.
#  ⚠️ The skill cannot force the session model itself (user --model) — casting applies to SUBAGENTS.
echo "[dynamic workflow casting]"
WF_CODE_MODEL="$(cfg_get workflow.casting.coding.model sonnet)"
WF_CODE_EFFORT="$(cfg_get workflow.casting.coding.effort xhigh)"
WF_MAX="$(cfg_get workflow.max_subagents 8)"
mkdir -p .claude
if command -v python3 >/dev/null 2>&1; then
  python3 - "$WF_CODE_MODEL" "$WF_CODE_EFFORT" "$WF_MAX" <<'PY' 2>/dev/null && echo "  ✓ casting recorded: coding=$WF_CODE_MODEL·$WF_CODE_EFFORT (reasoning/verification inherit the main session) max_subagents=$WF_MAX" || echo "  · settings.json merge failed — record manually"
import json,sys,os
model,effort,mx=sys.argv[1],sys.argv[2],int(sys.argv[3])
p=".claude/settings.json"
d=json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d.setdefault("ultraloop",{})["workflow"]={"casting":{"coding":{"model":model,"effort":effort}},"max_subagents":mx}
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
else
  echo "  · python3 missing — record ultraloop.workflow manually in .claude/settings.json"
fi

# ── 6.7 ★ bootstrap completion marker (for auto-forced entry, SKILL §0) ───────────────
#  When pm/loop entry finds no marker, bootstrap_repo.sh is run automatically (idempotent).
echo "[bootstrap marker]"
VER="$(python3 -c 'import json;print(json.load(open("'"$SKILL_DIR"'/.claude-plugin/plugin.json"))["version"])' 2>/dev/null || echo '?')"
# ★ Do not freeze an incomplete bootstrap as a success — the marker is written only when the required
#   prerequisites (gh-roadmap dependency + self-hosted runner) are secured. If absent, the next pm/loop entry
#   auto re-bootstraps (SKILL §0). A runner query failure ("?") may be a permission issue, so it does not
#   block (the agent re-verifies in the first loop).
if [ -z "$GHR_DIR" ]; then
  echo "  ✗ marker skipped — gh-roadmap (★ required dependency) absent. Auto-retried on re-entry after installation."
elif [ "$RUNNERS_ONLINE" = "0" ]; then
  echo "  ✗ marker skipped — 0 self-hosted runners (CI stays queued forever). Auto-retried on re-entry once a runner is secured."
else
  printf 'ultraloop bootstrap ok\nversion=%s\n' "$VER" > .claude/.ultraloop-bootstrapped 2>/dev/null \
    && echo "  ✓ .claude/.ultraloop-bootstrapped (version=$VER)" || echo "  · marker write failed"
fi

# ── 7. initial commit ────────────────────────────────────────────────────────
echo "[seed commit]"
git add -A 2>/dev/null || true
git commit -m "chore(ultraloop): bootstrap roadmap/CI-CD/goal-gate scaffolding" >/dev/null 2>&1 \
  && echo "  ✓ committed" || echo "  · no changes (idempotent) or commit failed"

echo "== bootstrap done =="
