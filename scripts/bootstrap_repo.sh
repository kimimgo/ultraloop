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

# ── 2. 보드(Projects v2) 멱등 — 권한 있을 때만 ──────────────────────────────
echo "[board]"
PNODE="$(cfg_get roadmap.project_node_id "")"
if [ -n "$PNODE" ]; then
  echo "  ✓ project_node_id 이미 기록됨(멱등 통과): $PNODE"
else
  echo "  · 보드 생성은 project-scope 토큰 필요. 에이전트가 roadmap-model.md §4(query-then-create)대로:"
  echo "    1) gh project list --owner <OWNER> 로 제목 조회 → 없으면 gh project create"
  echo "    2) assets/project-fields.json 의 필드/옵션 멱등 생성"
  echo "    3) 생성된 node-id/number 를 ultraloop.config.yaml(roadmap.project_node_id/number)에 기록"
  echo "    실패 시 폴백: Milestone+라벨(roadmap-model §6) + PROGRESS 뷰에 명시"
fi

# ── 3. 템플릿/워크플로 복사 ─────────────────────────────────────────────────
echo "[templates]"
mkdir -p .github/workflows .github/ISSUE_TEMPLATE
cp -n "$SKILL_DIR/assets/workflows/"*.yml .github/workflows/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/issue_templates/"*.md .github/ISSUE_TEMPLATE/ 2>/dev/null || true
cp -n "$SKILL_DIR/assets/pr_template.md" .github/pull_request_template.md 2>/dev/null || true
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

# ── 7. 초기 커밋 ────────────────────────────────────────────────────────────
echo "[seed commit]"
git add -A 2>/dev/null || true
git commit -m "chore(ultraloop): bootstrap roadmap/CI-CD/goal-gate scaffolding" >/dev/null 2>&1 \
  && echo "  ✓ committed" || echo "  · 변경 없음(멱등) 또는 커밋 실패"

echo "== bootstrap done =="
