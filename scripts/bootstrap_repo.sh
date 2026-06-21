#!/usr/bin/env bash
# bootstrap_repo.sh — 최초 1회 레포 셋업(멱등). 이미 됐으면 통과한다.
# 하는 일: 전제 probe → 라벨 → 보드(멱등 query-then-create) → 템플릿/워크플로 →
#          main 보호(review=0) → Environments(staging 자동/production HITL) →
#          goal Stop훅 설치(절대경로 치환) → CLAUDE.md/PROGRESS.md 시드 → 초기 커밋.
# 비결정: Projects v2 보드/Environments 는 권한·플랜 의존이라 *시도하고, 실패하면 또렷이 알리고 폴백 안내*.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SDIR/.." && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

REPO="$(ue_repo)"; DEFB="$(cfg_get default_branch main)"
echo "== ultraloop bootstrap =="; echo "repo=$REPO branch=$DEFB"

# ── 0. 전제 probe (없으면 또렷이 경고; silent degrade 금지) ──────────────────
probe() { command -v "$1" >/dev/null 2>&1 && echo "  ✓ $1" || echo "  ✗ $1  ($2)"; }
echo "[probe]"
probe git    "필수";  probe gh "필수"
probe docker "E2E: 폴백=README 단일명령 기동"
probe python3 "config/보드 파싱 권장"
TOKEN_ENV="$(cfg_get roadmap.token_env UE_PROJECT_TOKEN)"
[ -n "${!TOKEN_ENV:-${GH_TOKEN:-}}" ] && echo "  ✓ project-scope token($TOKEN_ENV)" || echo "  ✗ project-scope token  (Projects v2 자동화 불가 → 폴백 Milestone+라벨, roadmap-model §6)"
DTOKEN_ENV="$(cfg_get discord.token_env ULTRALOOP_DISCORD_BOT_TOKEN)"
[ -n "${!DTOKEN_ENV:-}" ] && echo "  ✓ discord bot token($DTOKEN_ENV)" || echo "  · discord bot token 없음  (승인 게이트웨이 폴백=webhook/console, notify-approval.md)"
echo "  · 브라우저 MCP 가용성은 첫 loop ①에서 에이전트가 probe해 PROGRESS 뷰에 기록"

# ── 0.1 의존 스킬 probe (references/dependencies.md) — gh-roadmap=보드 권위(필수), 나머지=폴백 가능 ──
echo "[skills]"
GHR_DIR=""
for d in "$HOME/.claude/skills/gh-roadmap" "$HOME"/.claude/plugins/*/skills/gh-roadmap; do
  [ -f "$d/SKILL.md" ] && { GHR_DIR="$d"; break; }
done
[ -n "$GHR_DIR" ] && echo "  ✓ gh-roadmap (보드 구조/셋업 권위): $GHR_DIR" \
  || echo "  ✗ gh-roadmap 없음 — 보드 뷰·로드맵·빌트인 워크플로 자동화 불가(★필수 의존). 설치 권장(references/dependencies.md)."
for s in product-strategy outcome-roadmap strategy-red-team prioritization-frameworks tdd-workflow; do
  [ -d "$HOME/.claude/skills/$s" ] && echo "  ✓ $s" || echo "  · $s 없음 (폴백: ultraloop 직접 수행)"
done

[ -n "$REPO" ] || { echo "✗ repo 미해석 — config.repo 또는 슬래시 인자(/ultraloop owner/name)"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "✗ gh 필요"; exit 1; }

# ── 0.5 레포 부재 시 생성 (신규 기획, §4.1.1) ───────────────────────────────
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  VIS="$(cfg_get repo_visibility private)"
  echo "[repo create] $REPO 미존재 → gh repo create --$VIS"
  if gh repo create "$REPO" "--$VIS" -d "ultraloop project" >/dev/null 2>&1; then
    echo "  ✓ created ($VIS)"
    git rev-parse --git-dir >/dev/null 2>&1 || git init -q
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$REPO.git" 2>/dev/null || true
  else
    echo "  ✗ 생성 실패(권한/이름 중복?) — 수동 'gh repo create $REPO' 후 재실행"; exit 1
  fi
fi

# ── 1. 라벨(멱등) ───────────────────────────────────────────────────────────
echo "[labels]"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys;[print(l["name"],l["color"],l.get("description","")) for l in json.load(open(sys.argv[1]))]' \
    "$SKILL_DIR/assets/labels.json" 2>/dev/null | while read -r name color desc; do
    gh label create "$name" --color "$color" --description "$desc" -R "$REPO" 2>/dev/null \
      || gh label edit "$name" --color "$color" --description "$desc" -R "$REPO" 2>/dev/null || true
  done
  echo "  ✓ labels synced"
else
  echo "  · python3 없음 — 라벨 수동 생성 필요(assets/labels.json)"
fi

# ── 2. 보드(Projects v2) — gh-roadmap 위임(보드 구조/셋업 권위) · 골든 템플릿 복제 ──
#  ⚠️ 뷰·Roadmap 레이아웃·빌트인 워크플로는 API 생성 불가(검증) → copyProjectV2(골든 템플릿)가 유일 자동화.
echo "[board → gh-roadmap]"
PNODE="$(cfg_get roadmap.project_node_id "")"
TEMPLATE="$(cfg_get roadmap.template_node_id "")"
if [ -n "$PNODE" ]; then
  echo "  ✓ project_node_id 이미 기록됨(멱등 통과): $PNODE"
elif [ -n "$GHR_DIR" ]; then
  echo "  · 보드 구조/셋업 = gh-roadmap 권위(references/dependencies.md). 다음으로 셋업:"
  echo "    1) cp $GHR_DIR/config.example.yaml ./gh-roadmap.config.yaml"
  echo "       → board.owner=${REPO%%/*} · board.title 설정 · repos:[{name:$REPO}]"
  if [ -n "$TEMPLATE" ]; then
    echo "       → board.template_node_id=$TEMPLATE  (★ 골든 템플릿 → copyProjectV2 로 3뷰·로드맵·빌트인워크플로 복제)"
  else
    echo "       ⚠️ template_node_id 비움 → fresh 보드(로드맵 뷰·빌트인 워크플로 없음)."
    echo "          golden-template-setup.md 로 골든 템플릿 1회 구성 후 그 id 를 roadmap.template_node_id 에 기록 권장."
  fi
  echo "    2) bash $GHR_DIR/scripts/roadmap_bootstrap.sh   # 보드 복제/생성 + N레포 link + 필드(Horizon·Target Date)"
  echo "    3) bash $GHR_DIR/scripts/roadmap_view.sh check  # 뷰(ROADMAP_LAYOUT)·빌트인워크플로(enabled)·필드 검증"
  echo "    4) 생성된 project_node_id/number 를 ultraloop.config.yaml(roadmap.*)에 기록(멱등 키)"
else
  echo "  ✗ gh-roadmap 없음(★필수 의존) — 폴백: roadmap-model.md §4 query-then-create 로 보드/필드 직접 생성"
  echo "    (assets/project-fields.json: Status·Priority·Horizon·Target Date·E2E-Evidence 포함)."
  echo "    ⚠️ 로드맵 레이아웃 뷰·빌트인 워크플로는 골든 템플릿 필요(API 생성 불가) — gh-roadmap 설치 권장."
fi

# ── 3. 템플릿/워크플로 복사 ─────────────────────────────────────────────────
echo "[templates]"
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
cp -n "$SKILL_DIR/assets/workflows/"*.yml .github/workflows/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/issue_templates/"*.md .github/ISSUE_TEMPLATE/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/pr_template.md" .github/pull_request_template.md 2>/dev/null || true
# auto-add 워크플로 — 골든 템플릿이 유일하게 복제 못 하는 빌트인 워크플로(auto-add) 갭을 gh-roadmap 이 메운다.
[ -n "${GHR_DIR:-}" ] && [ -f "$GHR_DIR/assets/add-to-project.yml" ] && \
  cp -n "$GHR_DIR/assets/add-to-project.yml" .github/workflows/add-to-project.yml 2>/dev/null && \
  echo "  · auto-add.yml 복사(PROJECT_URL·ADD_TO_PROJECT_PAT secret 치환 필요 — golden-template-setup §C)" || true
[ -f PROGRESS.md ] || cp "$SKILL_DIR/assets/PROGRESS.template.md" PROGRESS.md 2>/dev/null || true
[ -f CLAUDE.md ]   || cp "$SKILL_DIR/assets/CLAUDE.template.md" CLAUDE.md 2>/dev/null || true
# specs/ 자리(Spec Kit 스펙 원본, §4.1.3). specify init 은 게이트에서 에이전트가 — 부트스트랩은 자리만.
mkdir -p "$(cfg_get spec.specs_dir specs)" 2>/dev/null && : > "$(cfg_get spec.specs_dir specs)/.gitkeep" 2>/dev/null || true
echo "  ✓ workflows/issue/pr/PROGRESS/CLAUDE/specs 시드(없을 때만)"
echo "  · CI 워크플로의 lint/test/build 는 스택에 맞게 에이전트가 적응(references/rules/*)"

# ── 3.5 ★ self-hosted 러너 확인 (강제 원칙, ci-cd-hitl.md §0) ────────────────
echo "[self-hosted runner]"
RUNNERS_ONLINE="$(gh api "repos/$REPO/actions/runners" --jq '[.runners[]|select(.status=="online")]|length' 2>/dev/null || echo "?")"
if [ "$RUNNERS_ONLINE" = "?" ]; then
  echo "  · 러너 조회 실패(권한?) — CI 대기 전 에이전트가 재확인 필수(ci-cd-hitl.md §0)"
elif [ "$RUNNERS_ONLINE" -ge 1 ] 2>/dev/null; then
  echo "  ✓ online self-hosted runner: $RUNNERS_ONLINE"
else
  echo "  ✗ self-hosted 러너 없음 — 모든 워크플로가 runs-on: self-hosted 라 CI가 영원히 queued."
  echo "    → 러너 부트스트랩: ~/.claude/scripts/gh-runner/BOOTSTRAP.md (멱등 설치, ci-cd-hitl.md §0)"
  echo "    설치 불가(sudo·타호스트)면 루프 진행 금지 + 알림(notify-approval.md)."
fi
# 기존 워크플로 드리프트 교정: GitHub-hosted 러너 발견 시 self-hosted 로 강제 치환.
if grep -rln 'runs-on:.*\(ubuntu\|macos\|windows\)-' .github/workflows/ >/dev/null 2>&1; then
  sed -i 's/runs-on:[[:space:]]*\(ubuntu\|macos\|windows\)-[a-z0-9.-]*/runs-on: self-hosted   # ★ 강제 교정: self-hosted 원칙 (ci-cd-hitl.md §0)/' .github/workflows/*.yml 2>/dev/null || true
  echo "  ✓ GitHub-hosted runs-on 발견 → self-hosted 로 교정"
fi

# ── 4. main 보호(review=0 = 무인 auto-merge, 봇 바이패스) ────────────────────
echo "[branch protection]"
gh api -X PUT "repos/$REPO/branches/$DEFB/protection" -H "Accept: application/vnd.github+json" \
  -f 'required_status_checks[strict]=true' -F 'required_status_checks[contexts][]=' \
  -F 'enforce_admins=false' \
  -f 'required_pull_request_reviews[required_approving_review_count]=0' \
  -F 'restrictions=' -F 'allow_force_pushes=false' -F 'allow_deletions=false' \
  >/dev/null 2>&1 && echo "  ✓ protected (review=0)" || echo "  · 보호 설정 실패(플랜/권한) — PROGRESS 뷰에 기록하고 진행"

# ── 5. Environments(staging 자동 / production HITL) ─────────────────────────
echo "[environments]"
gh api -X PUT "repos/$REPO/environments/staging" >/dev/null 2>&1 && echo "  ✓ staging" || echo "  · staging env 실패(플랜)"
REV="$(cfg_get hitl.reviewers '[]')"
echo "  · production env = required reviewers(HITL). reviewers=$REV"
echo "    (개인레포/플랜 제약 시 cd.yml의 수동 승인 단계로 폴백 — ci-cd-hitl.md)"
gh api -X PUT "repos/$REPO/environments/$(cfg_get hitl.gated_environment production)" >/dev/null 2>&1 || true

# ── 6. goal Stop훅 설치(.claude/settings.json, 절대경로 치환) ────────────────
echo "[goal stop-hook]"
if [ "$(cfg_get engine.goal.install_stop_hook true)" = "true" ]; then
  mkdir -p .claude
  SNIP="$(sed "s#__ULTRALOOP_SKILL_DIR__#$SKILL_DIR#g" "$SKILL_DIR/assets/hooks/settings.snippet.json")"
  if [ -f .claude/settings.json ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$SKILL_DIR" <<'PY' 2>/dev/null && echo "  ✓ Stop훅 병합" || echo "  · settings.json 병합 실패 — 수동 추가 필요"
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
    printf '%s\n' "$SNIP" > .claude/settings.json && echo "  ✓ Stop훅 설치(.claude/settings.json)"
  fi
  echo "  · 가드 항상 ON: max_iterations/lock/budget/dead-man (engine-loop-and-goal §3)"
else
  echo "  · goal.install_stop_hook=false — 게이트 미설치(프롬프트 루프만)"
fi

# ── 6.5 ★ worktree 최적화(.claude/settings.json worktree.baseRef) ───────────
# 병렬 레인은 isolation:"worktree" 로 격리 실행된다. 레인이 '어디서 분기'하느냐를 고정해
# 재현성을 확보하고 미푸시 로컬 작업이 레인에 새지 않게 한다(worktree-strategy.md §0).
echo "[worktree baseRef]"
BASEREF="$(cfg_get worktree.base_ref fresh)"
case "$BASEREF" in fresh|head) ;; *) echo "  · 알 수 없는 base_ref='$BASEREF' → fresh 로 보정"; BASEREF=fresh ;; esac
mkdir -p .claude
if command -v python3 >/dev/null 2>&1; then
  python3 - "$BASEREF" <<'PY' 2>/dev/null && echo "  ✓ worktree.baseRef=$BASEREF 기록(.claude/settings.json)" || echo "  · settings.json 병합 실패 — 수동: \"worktree\":{\"baseRef\":\"$BASEREF\"}"
import json,sys,os
ref=sys.argv[1]; p=".claude/settings.json"
d=json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d.setdefault("worktree",{})["baseRef"]=ref
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
else
  echo "  · python3 없음 — .claude/settings.json 에 \"worktree\":{\"baseRef\":\"$BASEREF\"} 수동 추가"
fi
echo "  · fresh=origin/<default>에서 레인 분기(권장) | head=로컬 미푸시 커밋 위 (worktree-strategy.md §0)"

# ── 6.6 ★ Workflow 오케스트레이션 설정(.claude/settings.json, references/workflow-orchestration.md) ──
#  config.workflow 의 model/effort/max_subagents 를 기록 = Workflow 단계 서브에이전트 기본값.
#  ⚠️ 세션 모델 자체는 스킬이 강제 못 함(사용자 --model) — 이건 '권장 힌트'. by_phase 오버라이드는 SKILL 이 직접 읽음.
echo "[workflow orchestration]"
WF_MODEL="$(cfg_get workflow.agents.model opus)"
WF_EFFORT="$(cfg_get workflow.agents.effort xhigh)"
WF_MAX="$(cfg_get workflow.agents.max_subagents 8)"
mkdir -p .claude
if command -v python3 >/dev/null 2>&1; then
  python3 - "$WF_MODEL" "$WF_EFFORT" "$WF_MAX" <<'PY' 2>/dev/null && echo "  ✓ workflow 기록: model=$WF_MODEL effort=$WF_EFFORT max_subagents=$WF_MAX" || echo "  · settings.json 병합 실패 — 수동 기록"
import json,sys,os
model,effort,mx=sys.argv[1],sys.argv[2],int(sys.argv[3])
p=".claude/settings.json"
d=json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d.setdefault("ultraloop",{})["workflow"]={"model":model,"effort":effort,"max_subagents":mx}
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
else
  echo "  · python3 없음 — .claude/settings.json 에 ultraloop.workflow 수동 기록"
fi

# ── 6.7 ★ 부트스트랩 완료 마커 (자동 강제 진입용, SKILL §0) ───────────────────
#  pm/loop 진입 시 이 마커가 없으면 자동으로 bootstrap_repo.sh 를 실행한다(멱등).
echo "[bootstrap marker]"
VER="$(python3 -c 'import json;print(json.load(open("'"$SKILL_DIR"'/.claude-plugin/plugin.json"))["version"])' 2>/dev/null || echo '?')"
printf 'ultraloop bootstrap ok\nversion=%s\n' "$VER" > .claude/.ultraloop-bootstrapped 2>/dev/null \
  && echo "  ✓ .claude/.ultraloop-bootstrapped (version=$VER)" || echo "  · 마커 기록 실패"

# ── 7. 초기 커밋 ────────────────────────────────────────────────────────────
echo "[seed commit]"
git add -A 2>/dev/null || true
git commit -m "chore(ultraloop): bootstrap roadmap/CI-CD/goal-gate scaffolding" >/dev/null 2>&1 \
  && echo "  ✓ committed" || echo "  · 변경 없음(멱등) 또는 커밋 실패"

echo "== bootstrap done =="
