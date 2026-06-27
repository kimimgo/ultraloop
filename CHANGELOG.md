# Changelog

All notable changes to ultraloop are documented here. Versioning is [SemVer](https://semver.org/).

## 0.6.1

### Fixed (3-model audit — Codex gpt-5.5 + Claude Opus; 기본 동작 영향 없음 — 게이트 강화·정합)
- **Status 옵션명 통일** — `meta_sync.sh`·loop/pm SKILL 의 `In Progress`(공백)/`Todo` → 정본
  (`project-fields.json`: `In-Progress`/`Ready`). 카드 이동 실패(exit 5)·경고 미발화 해소.
- **cost_guard 카운터 오염** — goal Stop 게이트가 매 정지 시도마다 loop-count 를 올리던 것 분리(`--no-tick`).
- **E2E 판정 강화** — `grep -i PASS`(`password`/`bypass` 오탐) → `**PASS**`/`**FAIL**` 최종결과 마커.
  `goal_check` 도 리포트 개수만 보던 것 → 미해결 FAIL/PASS 마커 내용 검증.
- **승인 보안** — `approve_bot` approver 빈 목록=누구나 승인 → fail-closed; `approval_queue` 의 `bash -c`
  명령주입 → 인자 배열 직접 실행; `approve_bot` 기본 config 경로 = 대상 레포 cwd.
- **디스크 watchdog** — `e2e_down` 의 전역 `docker system prune`(공유 호스트 타 프로젝트 캐시 삭제) →
  dangling 이미지/빌드 캐시만.
- **E2E 격리** — `e2e_up` 의 `UE_LANE` 미export(레인 DB 볼륨 공유)·`.env.e2e` 미주입 → export + `--env-file`;
  compose 모드 헬스 타임아웃은 실패로(조용한 성공 금지).
- **보드 페이지네이션** — `roadmap_sync`/`meta_sync`/`board` 의 GraphQL `first:100` 고정 →
  `--paginate` cursor(100+ 카드 누락 방지).
- **부트스트랩 마커** — gh-roadmap 부재·러너 0 대에도 완료 마커를 찍던 것 → 전제 충족 시에만(미완 고착 방지).
- **HITL reviewer 등록** — production Environment 에 reviewer payload 실제 등록(이전엔 environment 만 생성).
- **prod-deployed 마커** — goal 종료조건이 요구하나 생성처가 없던 `.ultraloop/prod-deployed` →
  `scripts/mark_deployed.sh` 신설 + ci-cd-hitl 배선.
- **worktree GC** — `git diff`(untracked 못 봄) → `git status --porcelain`(미커밋 보존 정확).
- **design `integrate.py`** — foamlab/m11 절대경로·토큰 하드코딩 → config/CLI 기반 일반 통합기.
- **README** — 2스킬/v0.4.0 stale → design→pm→loop / v0.6.0 정합.
- budgets `max_tokens`/`ci_minutes_per_day` 주석을 best-effort(미구현)로 정직화.

## 0.6.0

### Added
- **신뢰도 eval 게이트 (pass@k / pass^k)** — `eval-harness` 스킬을 의존성으로 배선. `config.eval.enabled=true`
  면 카드 검증에 신뢰도 차원을 더한다: critical 카드(`eval.critical_labels`)는 핵심 테스트/E2E 를 반복
  실행해 pass^k=1.0(전부 통과)을 요구하고, 그 외 카드는 pass@k ≥ `eval.capability_threshold` 를 잰다.
  스킬 부재 시 `eval.max_k` 회 반복 실행으로 폴백. 증거는 `.claude/evals/<card>.log`.
- 배선: `config.example.yaml`(`eval:` 블록), `references/dependencies.md`(§2 맵·§3 규칙),
  `references/loop-protocol.md`(⑥ E2E 단계), `references/definition-of-done.md`(DoD 체크리스트).
- 기본 `eval.enabled=false` — 끄면 기존 루프 동작에 영향 없음(하위호환).

## 0.5.0

### Added
- **New skill `ultraloop:design`** — the design half of the loop, run BEFORE pm. Orchestrates Google Stitch
  (foundation) + the harness's verified design tools (taste-design, artifact-design, impeccable, taste-skill,
  frontend-design, stitch-{design,build,utilities}, gstack-design-*, tri-model-review, gemini-image-eval,
  playwright-cli, artifacts traefik publish) into ONE verified loop:
  scope → cold multi-model critique (codex+gemini, no leading, N angles incl. domain lens) → design-system
  foundation → Stitch generate → integrate (token-normalize + cross-nav + real data canvases) →
  render-verify → re-score → iterate to a numeric target → hand an approved DESIGN.md to pm.
- References: `design-loop-protocol.md`, `design-tools-map.md`, `stitch-foundation.md`, `community-refs.md`.
- Assets: `assets/design/{DESIGN.md,SITE.md,next-prompt.md}.template`, `integrate.py`, `charts.js`.
- Script: `scripts/design_env_check.sh` (idempotent tool-availability check).
- Skill order is now **design → pm → loop**; plugin/marketplace manifests + keywords updated.
- Empirically validated on foamlab (2026-06-23): a 5/100 "color-copied" mockup rebuilt to codex 84 /
  gemini 92 via this loop. Stitch prompting rules + MCP connection captured from official docs + live runs.

## 0.4.1

### Fixed
- `references/messaging.md`: forbidden-token list still named the old skill name (`build` → `loop`).
- `assets/project-fields.json`: added `Start Date` (DATE) for parity with `gh-roadmap` `fields.json`
  (the Roadmap view needs a Start+Target pair to draw duration bars on the fallback path).

## 0.4.0

### Changed
- **Renamed skill `build` → `loop`** (`ultraloop:build` → `ultraloop:loop`).
- **ultraloop now ORCHESTRATES proven skills** rather than reimplementing them.
  `gh-roadmap` is declared a **REQUIRED dependency** (the authority for board
  structure/setup). See new `references/dependencies.md`.

### Added
- **Workflow orchestration enforced.** Phases now run through the Claude Code
  Workflow tool (`opus` / `ultracode` / `dynamic`) via new `config.workflow`
  (per-agent model/effort/max_subagents plus `by_phase`). See new
  `references/workflow-orchestration.md`.
- **Bootstrap auto-enforced on skill entry** via a `.claude/.ultraloop-bootstrapped`
  marker.
- **Golden-template provisioning of board views.** Board views, the Roadmap
  layout, and built-in workflows are now provisioned by cloning a `gh-roadmap`
  golden template (`copyProjectV2`); `config.roadmap.template_node_id` selects it.
  Project fields gain **Horizon** and **Target Date**, and the auto-add workflow
  is copied from `gh-roadmap`.

## 0.3.0

### Added
- **README: philosophy + per-loop flowcharts.** New *Philosophy* section (8 principles) and a
  *How the loop works* section with mermaid flowcharts for the overall loop, the PM loop, the
  Build loop, and the `/goal` stop-gate.
- **README: Bootstrap section** documenting what `bootstrap_repo.sh` sets up, including the new
  worktree optimization.
- **Worktree optimization in bootstrap.** `bootstrap_repo.sh` now writes `worktree.baseRef`
  (from `config.worktree.base_ref`, default `fresh`) into the target repo's
  `.claude/settings.json`, fixing where parallel build lanes branch (`fresh` = `origin/<default>`,
  reproducible; `head` = local unpushed HEAD).
- `config.worktree.base_ref` knob in `config.example.yaml`.
- `references/worktree-strategy.md` §0 documenting `baseRef` semantics and the recommended `fresh`.

## 0.2.0
- pm/build two-skill plugin: `ultraloop:pm` (plan → write the board) and `ultraloop:build`
  (read the board → TDD + pre-merge E2E → ship), with the GitHub Projects board as the single
  source of truth.
