# Git · 이슈 · 브랜치 · 보드 자동화 (git-and-issues)

목표: 모든 개발 이력이 issue ↔ branch ↔ commit ↔ PR ↔ board card ↔ release 로 추적 가능.

## 1. 브랜치 전략 (trunk-based + 단명 브랜치)
- `main` — 항상 배포 가능. **보호**: 직접 push 금지, PR 필수, required status checks 통과,
  강제푸시/삭제 금지, `required_approving_review_count=0`(무인 auto-merge 허용 — 봇 바이패스, REQ-CD-4).
- 작업 브랜치 — 이슈 1:1: `feat/<issue#>-<slug>` · `fix/…` · `test/…` · `refactor/…` · `chore/…` · `docs/…`.
- 머지 = **squash**. 머지 후 브랜치·worktree 삭제.

## 2. 이슈 (작업의 시작점)
- 모든 작업은 이슈에서 시작: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/new_task.sh <type> "<title>" ["<body>"]`
  → 라벨 + 보드 카드 생성, `<type>/<issue#>-<slug>` 브랜치 체크아웃, 카드 Status=In-Progress.
- 라벨(`assets/labels.json`): `type:*`, `bug`, `edge-case`, `blocked`, `security`, `perf`, `hitl`, `e2e:fail`, `epic`.
  Status는 라벨이 아니라 **보드 필드**로 관리(SoT).
- 버그/엣지/발산은 발견 즉시 이슈로(루프가 나중에 소비). `blocked` 는 에스컬레이션 신호.

## 3. 커밋 (Conventional Commits) — 제목 결정적 / 본문 한국어
형식 `type(scope): subject`. **type·scope·subject 는 결정적 템플릿**(changelog/semver/보드 자동화 안정),
**본문(왜/무엇)만 LLM 한국어**(비결정). 상세 `messaging.md`. 원자성: 한 커밋 = 한 변경.

## 4. PR (이슈 + 카드를 닫는 단위)
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/ship_pr.sh ["title"]`
- push → PR(본문 `Closes #<issue>` + **E2E 증거 섹션** `assets/pr_template.md`).
- CI 감시(`gh pr checks --watch`) → 녹색 → **⑥ merge 전 E2E** → 통과 시 `gh pr merge --squash --auto --delete-branch`.
- **증거 추적(#20)**: E2E 증거 경로를 merge commit trailer(`E2E-Evidence: <path>`) + 보드 카드 `E2E-Evidence`
  필드에 기록(squash 후에도 추적). CI 실패 → 같은 브랜치 수정 재시도(보호 우회 금지).

## 5. 보드 자동화 (project-scope PAT/App — REQ-CI-3)
- 카드 생성·필드 전이(Status/Evidence)는 **project-scope 토큰**으로(`config.roadmap.token_env`,
  기본 env `UE_PROJECT_TOKEN`). 기본 `GITHUB_TOKEN` 으론 Projects v2 mutation 불가.
- 없으면 부트스트랩이 폴백(Milestone+라벨, `roadmap-model.md` §6)으로 전환하고 PROGRESS 뷰에 명시.
- 토큰 만료는 사전 점검(`observability.md` 자격증명 수명).

## 6. 릴리즈 (SemVer)
배포 가치가 쌓이면 `main` 에서 SemVer 태그 `vX.Y.Z`(feat→minor·fix→patch·호환깨짐→major) → CD가 빌드/
배포 + GitHub Release. 노트는 머지된 PR/이슈로 구성(추적성).

## 7. 추적성 자가 체크
모든 머지가 PR 경유? 모든 PR이 이슈 닫음? 모든 Done 카드에 E2E-Evidence? 열린 `blocked` 0?
PROGRESS 뷰 최신? — 매 loop ①/⑧에서 확인(`progress.sh`).
