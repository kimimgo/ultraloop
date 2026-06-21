# CI/CD — 계층 CI + merge 전 E2E + HITL 배포 (ci-cd-hitl)

핵심: **매 push CI → 녹색 → merge 전 E2E 통과 → squash merge → CD(staging 자동, production=HITL)**.
승인 게이트는 Claude가 아니라 **GitHub 서버**가 강제 → 우회 불가. **전 구간 self-hosted 러너(§0)**.

## 0. ★ self-hosted 원칙 — 강제 (REQ-CI-0)
모든 GitHub Actions job은 **`runs-on: self-hosted`(홈랩 러너)**. GitHub-hosted(`ubuntu-latest`,
`macos-*`, `windows-*` 등) **금지** — 분당 과금·사용량 한도·홈랩 자원(GPU/도커) 미접근 때문.
- **템플릿**: `assets/workflows/*.yml` 은 이미 self-hosted. 라벨 추가만 허용
  (예: `[self-hosted, linux, x64]`, `config.ci.runs_on`) — hosted 로 되돌리기 금지.
- **드리프트 교정**: 부트스트랩·루프 중 워크플로를 만들거나 고칠 때 `ubuntu-latest` 등이 보이면
  **그 자리에서 self-hosted 로 교정**한다(`rules/_base.md` 드리프트 교정과 동일 취급).
- **러너 확인 게이트**: CI 녹색을 기다리기 전에 러너 온라인을 확인한다 —
  `gh api repos/<repo>/actions/runners --jq '.runners[]|select(.status=="online")'`.
  러너 없음 = job 무한 queued → **러너 부트스트랩(아래) 먼저 시도**, 불가하면 루프 진행 금지 + 알림(`notify-approval.md`).
- **러너 부트스트랩**: `~/.claude/scripts/gh-runner/BOOTSTRAP.md` = 검증된 플레이북(2026-06-12, OCMS 3레포).
  전제 점검(gh admin 스코프·user/org·런타임) → A 러너 설치(`setup-self-hosted-runner.sh OWNER/REPO --service
  [--python]`, 멱등) → B 워크플로 전환 PR(`convert-workflows.sh`) → C 레포고유 함정 3개 로그 판별
  (pnpm핀↔Node 불일치·CD compose 포트충돌·트리거 오판 — 스크립트가 못 고침, 에이전트가 판별) → D green
  증거 검증. ⚠️ Claude 고유 함정 2개 포함: bare 데몬 기동은 샌드박스가 죽임(exit 144)→`--service`(systemd)
  권장 또는 dangerouslyDisableSandbox, secret-guard가 커맨드 문자열의 `.env`를 차단→스크립트 파일 경유 호출.
  sudo 불가·타 호스트면 알림에 호출법 한 줄을 실어라:
  "`~/.claude/scripts/gh-runner/BOOTSTRAP.md` 읽고 `OWNER/REPO`에 self-hosted CI/CD 적용해줘".
- **배포 타깃도 self-hosted 인프라(홈랩)가 기본**(`config.deploy`). 외부 클라우드 배포는 §14 고위험(승인 큐).

## 1. CI — 매 push, 폭풍 제어 (REQ-CI-1)
`assets/workflows/ci.yml`:
- 모든 push가 CI 트리거. 단 **`concurrency: ci-<branch>, cancel-in-progress: true`**(브랜치당 최신만) +
  **계층화**(커밋=빠른 lint/type/unit, PR-ready=풀 test+cov+build+스모크) + **path 필터**.
- 비용 폭주 방지(`cost_guard.sh`와 연동, REQ-CD-3).

## 2. 항시 감시 → merge 전 E2E (REQ-CI-2)
push 후 `gh pr checks --watch` 로 감시(`ship_pr.sh`). 녹색 → **⑥ merge 전 E2E**(`e2e-production.md`) →
통과해야 squash merge. 실패 → 같은 브랜치 수정 재시도(보호 우회 금지).

## 3. 보드 권한 (REQ-CI-3)
보드 자동화/카드 전이 = **project-scope PAT/App**(기본 `GITHUB_TOKEN` 불가). 없으면 부트스트랩 실패 +
폴백 안내(`roadmap-model.md` §6).

## 4. CD — staging 자동 / production HITL (REQ-CD-1)
`assets/workflows/cd.yml`: `main` 머지/`v*` → build → staging 자동배포 → 스모크 → **production =
Environment 승인(HITL)**. E2E가 merge 전이라 staging 스모크는 **얇은 재확인**.
- `deploy-production` 은 `environment: production`(required reviewers = `config.hitl.reviewers`)라 GitHub가
  job을 일시정지하고 사람 승인을 요구. 승인 후에만 배포 → 헬스 → GitHub Release.

## 5. HITL 확인 루프 (Claude의 행동)
1. 대기 감지: `gh run list/view` 로 production job "waiting" 확인.
2. **알림**(Discord + 보조 콘솔): 승인 대기 URL + staging 스모크 결과 + 배포될 버전/PR 목록.
3. **병행**: 승인 전까지 강행하지 않고 다른 비배포 작업 계속(승인 큐와 동일 철학, `notify-approval.md`).
4. 결과: 승인 → 배포/헬스/보고. 거부 → 원인 이슈(`hitl`/`bug`) → 수정 루프.

## 6. 회귀·롤백·서킷브레이커
- `nightly-e2e.yml` 전체 회귀(REQ-CD-2). 롤백 `workflow_dispatch(rollback_to)`.
- **비용 서킷브레이커**(REQ-CD-3): CI 분/동시 잡/일일 실행 상한 초과 시 차단 + 알림(`config.budgets.ci_minutes_per_day`).

## 7. 보호규칙 (REQ-CD-4)
`main` 보호 + `required_approving_review_count=0`(무인 auto-merge). 사람 리뷰가 필요하면 봇 바이패스 정책을
**PROGRESS 뷰에 기록**(추적성 tradeoff). 시크릿은 Actions/Environment Secrets만(평문 금지).
