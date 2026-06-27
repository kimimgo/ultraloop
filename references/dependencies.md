# 의존 스킬 (dependencies) — ultraloop = 오케스트레이터 ★

ultraloop 은 바퀴를 **재발명하지 않는다.** 검증된 고성능 스킬·플러그인을 *단계마다 호출*하고, 그 산출물을
보드로 수렴시킨다. 각 스킬이 없으면 직접 폴백하되 **산출물 형식은 맞춘다**. 부재는 silent degrade 하지 말고
PROGRESS 뷰/콘솔에 또렷이 남긴다.

---

## 1. 필수 의존 — gh-roadmap (보드 구조/셋업의 유일 권위) ★

**보드(GitHub Projects v2)의 생성·필드·뷰·Roadmap 레이아웃·빌트인 워크플로·멀티레포 링크·3-tier 계층
(sub-issue)·의존성(blocked-by)·상태 업데이트는 전부 `gh-roadmap` 스킬에 위임한다.** ultraloop 은 보드를
**소비만** 한다(읽기 / 카드 이동 / 코멘트). **두 SoT 금지** — 보드 구조를 ultraloop 이 직접 만들지 않는다.

| 용도 | gh-roadmap 스크립트 |
|---|---|
| 보드 부트스트랩(골든템플릿 copyProjectV2 복제 또는 fresh) + N레포 link + 필드/Status 정렬 | `roadmap_bootstrap.sh` |
| 뷰(ROADMAP_LAYOUT)·빌트인 워크플로(enabled)·필드 셋업 **검증** | `roadmap_view.sh check` |
| 3-tier 항목(이슈+보드+Horizon/Target Date/Status+sub-issue+Milestone) | `roadmap_item.sh` |
| 네이티브 의존성(blocked-by) | `roadmap_dep.sh` |
| 보드 헬스(ON_TRACK/AT_RISK) | `roadmap_status.sh` |

> ⚠️ **뷰·Roadmap 레이아웃·빌트인 워크플로·Insights 는 GitHub API 로 생성 불가**(검증됨). 유일한 자동화 =
> 사람이 골든 템플릿 보드 1개를 UI 로 구성 → `copyProjectV2` 복제(`config.roadmap.template_node_id`).
> 상세 = `gh-roadmap/references/golden-template-setup.md`.

---

## 2. 단계별 오케스트레이션 맵

| 단계 | 호출 스킬(있으면) | ultraloop 역할 |
|---|---|---|
| 전략 | `product-strategy` | 제품 전략 캔버스 받기 |
| 로드맵 | `outcome-roadmap` | output→outcome 로드맵(매 loop 점검 기준) |
| 적대 검증 | `strategy-red-team` | 가정 공격 + kill criteria — **통과 못 하면 스펙 진입 금지** |
| 스펙 | `speckit`(constitution→specify→clarify→plan→tasks→analyze→taskstoissues) | 스펙 권위 |
| 우선순위 | `prioritization-frameworks` | RICE/ICE 로 문제 우선순위화 |
| **보드** | **`gh-roadmap`** ★ | 보드·필드·뷰·로드맵·빌트인 워크플로·멀티레포 |
| Tier1 TDD | `tdd-workflow` | 단위/통합 (Red→Green→Refactor) |
| 품질(선택) | `gan-style-harness` / `gan-evaluator` | E2E 증거를 루브릭으로 채점 |
| 신뢰도 eval(선택) | `eval-harness` | 카드 검증을 pass@k/pass^k 로 — DoD 신뢰도 게이트(`config.eval.enabled`) |
| 검증·리뷰·배포(유도) | `gstack-qa` · `gstack-review` · `gstack-investigate` · `gstack-ship` | 있으면 활용(자체 스크립트는 폴백) |
| 다중에이전트 fan-out | (Claude Code **Workflow 도구**) | 단계 병렬화 — `workflow-orchestration.md` |

---

## 3. 규칙

- **있으면 호출, 없으면 폴백.** 스킬 부재 시 ultraloop 이 직접 수행하되 산출물 형식 동일. 부재는 명시(silent degrade 금지).
- **gstack 계열**은 loop 의 E2E/리뷰/배포 단계에서 *유도*(필수 아님). ultraloop `e2e_run.sh`·`ship_pr.sh` 는 폴백 경로.
- **eval-harness**는 `config.eval.enabled=true` 일 때만 — critical 카드(`eval.critical_labels`)는 pass^k=1.0, 그 외는 pass@k. 스킬 부재 시 ultraloop 이 핵심 테스트/E2E 를 `eval.max_k` 회 반복 실행으로 폴백(산출물 형식 동일, `.claude/evals/`).
- **부트스트랩 probe** 가 스킬 가용성을 점검(`~/.claude/skills`, `claude plugin list`). gh-roadmap 없으면 또렷이 경고.
- 이 모든 호출·도구는 **보드/이슈/PR/커밋의 외부 가시 문구에 노출하지 않는다**(`messaging.md` — 사람이 쓴 제품 언어로).
