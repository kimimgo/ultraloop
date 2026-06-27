# 루프 프로토콜 (loop-protocol) — 오케스트레이터 + 병렬 레인 + merge 전 E2E

1 loop = **오케스트레이터(순차 컨트롤러)** 가 병렬 레인을 fan-out → join 하는 한 사이클. 비결정적이다:
이슈 성격·스택·환경에 따라 매 loop 워크플로를 동적으로 구성한다.

## 0. 한 loop의 9단계

```
[오케스트레이터]
 ① 계획 점검    보드→PROGRESS 뷰 재생성(regen_progress.sh) · 로드맵 게이트(roadmap_sync.sh)
                · **보드 정합 수렴(meta_sync.sh reconcile — 닫힌 이슈인데 카드≠Done이면 멱등 수렴)**
                · **로드맵 전략 정합 점검(매 루프)**: 남은 카드들이 기획 게이트의 outcome-roadmap
                  전략 의도와 여전히 맞는가 — 드리프트(전략과 무관한 카드 증식, outcome 달성에 빠진
                  조각)가 보이면 새 작업을 만들지 말고 **게이트 재진입 신호로 보고**(§roadmap-model 5.1)
                · 환경점검(env-check.md) · 비용/heartbeat(cost_guard.sh, heartbeat.sh)
                · 승인 큐 drain(approval_queue.sh drain → 해결된 항목 unpark)
 ② 레인 편성    다음 Ready 이슈 N개(=worktree.max_lanes) — Depends-on 위배 X + 모듈 비충돌
                · stale worktree GC(worktree_mgr.sh gc, in-flight 보호) · 레인별 worktree 생성
[레인 병렬 ③~⑥ — worktree별 독립 (서브)에이전트]
 ③ Dynamic TDD  이슈에 맞는 워크플로 구성 → Red→Green→Refactor + 원자 커밋(한국어 본문)
 ④ push         계층 CI 트리거
 ⑤ CI 녹색      봇 QA(lint/type/test/build) 전부 통과 감시(ship_pr.sh 가 watch)
 ⑥ ★merge 전 E2E 실배포(레인 격리 포트)→에이전트 클릭/셸 시나리오→캡쳐 증거(e2e_*.sh)
                · 선택 GAN 품질 루프(config quality.gan_evaluator=true): gan-evaluator 에이전트가 E2E
                  증거를 이슈 수용기준 루브릭으로 채점 → threshold 미달 시 재작업·재평가. ★max_rounds
                  하드가드 — 초과 시 그 레인 Parked+승인큐(무한 품질 루프 금지)
                · 선택 신뢰도 eval(config eval.enabled=true): critical 카드(eval.critical_labels)는 핵심
                  테스트/E2E 를 반복 실행해 pass^k=1.0, 그 외는 pass@k≥threshold 측정(eval-harness 스킬,
                  없으면 max_k 회 반복 폴백) → 결과 .claude/evals/<card>.log. ★max_k 하드가드
[오케스트레이터]
 ⑦ join+merge   E2E 통과(merge-ready) 레인만 squash merge · 충돌 직렬화 해소
 ⑧ 보드 업데이트 카드 Done + E2E-Evidence 경로 · 버그/엣지 → 새 이슈 · 로드맵 수정(notify-only+감사)
                — 카드 이동·필드·증거는 `board.sh status|set|evidence`(graphql 통합 CLI). raw graphql 손작성 금지.
 ⑨ 종료 평가    보드 全 Done + DoD + prod HITL? — 아니오 → 다음 반복 페이싱(/loop) · 예 → 완료 보고
```
> N레포 공유 보드 모드면 ①에 **자기 inbox 확인**(MCP team_inbox_peek/team_inbox_consume, 또는 HTTP
> `GET /team/inbox/<세션명>?consume=true`, 예시 브로커 API)이 추가된다 — 메타의 지시가 message broker에 영속된다(`multi-repo-orchestration.md §5`).

## 1. 원칙
- **E2E는 merge 전(⑥)** — main에는 E2E 통과 코드만. "main 항상 배포가능"을 유지(REQ-LOOP-1).
- **실행 증거로만 ✅** — "돌아갔다 ≠ 맞았다"(REQ-LOOP-2).
- **PROGRESS 뷰는 보드에서 재생성** — 직접 기록 금지(REQ-LOOP-3, 경합 제거).
- **고위험 레인만 Parked + 승인 큐**, 다른 레인은 계속, 루프 전체는 안 멈춘다(REQ-LOOP-4).

## 2. 레인(병렬) 작업 단위
각 레인은 1 이슈 = 1 worktree = 1 (서브)에이전트. 레인 안에서 issue→TDD→push→CI→E2E→merge-ready.
오케스트레이터는 병렬성을 `worktree.max_lanes`(기본 2)로 제한하고, **모듈 디렉토리가 겹치지 않는** 이슈만
동시에 돌린다(머지 충돌 최소화). 자세한 worktree 규칙은 `worktree-strategy.md`.

## 3. 동적 워크플로(Tier 1)
이슈가 "버그 수정"이면 재현 테스트 먼저, "신규 기능"이면 수용기준→실패 테스트→구현, "리팩터"면 회귀
테스트 그린 유지 — 이렇게 이슈 성격에 맞춰 이번 사이클 워크플로를 짠다. 상세는 `tdd-layer.md`.

> ⚠️ **루프 중 `specs/`(스펙 본문·수용기준) 수정 금지 — 동결 상태**(§9.7). 스펙 변경이 필요하면 게이트
> 재진입에서만(`roadmap-model.md §5.1`). ⑧단계의 "로드맵 수정(notify-only)"은 **보드 카드 추가/이동**
> (버그·엣지 → 새 이슈)을 뜻하지, 동결된 스펙 본문 변경이 아니다 — 둘을 혼동하지 말 것.

## 4. join + merge (⑦)
- E2E를 통과해 merge-ready가 된 레인만 `ship_pr.sh` 로 squash merge.
- 동시에 여러 레인이 merge-ready면 **직렬화**해 충돌을 하나씩 해소(rebase/충돌 수정 커밋).
- merge 후 브랜치·worktree 정리(`worktree_mgr.sh`).

## 5. 재개 (crash-safe)
보드가 SoT라 세션이 끊겨도 손실 없다. 재개 시 `roadmap_sync.sh` 로 보드를 읽어 In-Progress/E2E/Parked
카드부터 그 지점에서 이어간다. PROGRESS.md 화해 불필요(보드가 진실, 뷰는 재생성).

## 6. 안티-스래싱
동일 블로커 반복은 strike. 단 E2E flake는 strike가 아니다(백오프 재시도 후 결정적 실패만 — `e2e-production.md`).
3-strike면 `blocked` 이슈 + 에스컬레이션. 고위험은 strike 전에 승인 큐로(§notify-approval).

## 7. 다음 반복 페이싱(⑨ → ①)
종료 미충족이면 `engine-loop-and-goal.md` 의 /loop 엔진으로 다음 깨어남을 정한다(ScheduleWakeup 또는 Cron).
충족이면 페이싱을 멈추고 `definition-of-done.md` 완료 보고를 출력한다.
