# Workflow 오케스트레이션 — opus · ultracode · dynamic ★

> ⚠️ **용어**: 여기 "워크플로"는 **Claude Code Workflow 도구**(다중에이전트 오케스트레이션)다.
> GitHub Projects **빌트인 워크플로**(닫힘→Done 자동화)와 전혀 다르다 — 그건 보드쪽이며 `gh-roadmap` /
> `roadmap-model.md` 가 다룬다. 둘을 섞지 마라.

`config.workflow` 가 제어한다: pm·loop 의 핵심 단계를 단일 에이전트로 순차 처리할지, **Workflow 도구로
다중에이전트 fan-out** 할지.

---

## 1. 강제의 현실 (정직)

스킬(마크다운)은 **세션 모델을 직접 못 바꾼다** — 모델은 사용자가 `--model` 로 정한다. 그래서 "opus 강제"는
다음으로 구현한다(하드 모델 강제가 아님):

1. Workflow/Agent 호출 시 **서브에이전트**의 `model`/`effort`/`agentType`/`isolation` 을 지정한다(이건 가능).
2. SKILL 이 핵심 단계를 **Workflow 로 오케스트레이션하도록 강하게 지시**한다.
3. 부트스트랩이 `config.workflow` 를 대상 레포 `.claude/settings.json` 에 기록한다(세션 기본 모델 *권장* 힌트).

> 하드 차단(PreToolUse 훅으로 비-Workflow 작업 거부)은 **쓰지 않는다** — 일반 작업을 방해하고 취약하다.

---

## 2. 설정 → Workflow/agent() 매핑

| `config.workflow` | 적용 |
|---|---|
| `orchestrate: true` | 핵심 단계를 Workflow 도구로 오케스트레이션(아래 패턴) |
| `mode: ultracode` | 단계를 `parallel()`/`pipeline()` 로 다중에이전트 fan-out |
| `mode: solo` | 단일 `agent()`(소규모 작업) |
| `pacing: dynamic` | 동적 페이싱 — `engine.loop.pacing` 과 정합 |
| `agents.model` | `agent(prompt, {model})` |
| `agents.effort` | `agent(prompt, {effort})` |
| `agents.max_subagents` | 동시성 캡 — 실제 동시 실행 = `min(값, 코어-2)` |
| `by_phase.pm` / `by_phase.loop` | 단계별 오버라이드(없으면 `agents` 기본값 상속) |

---

## 3. 단계별 패턴

- **pm 기획 체인** — 전략·로드맵·레드팀·스펙·우선순위를 fan-out.
  - 의존 단계는 `pipeline()`(전 단계 산출물이 다음 입력), 독립 다관점은 `parallel()`.
  - `strategy-red-team` 은 **배리어**: 통과 전 스펙 단계 진입 금지(`dependencies.md`).
  - `by_phase.pm` 의 model/effort/max_subagents 적용.
- **loop 레인** — Ready 카드 N 개를 레인으로 fan-out.
  - 각 레인 = `agent(..., {isolation: "worktree"})` — 파일 충돌 방지(`worktree-strategy.md`).
  - model/effort = `by_phase.loop`, 동시 레인 수 ≤ `max_subagents` 이자 ≤ `worktree.max_lanes`.
- **검증** — E2E/리뷰를 adversarial 다관점으로(여러 verifier 가 독립 채점, 다수결).

---

## 4. 안전

- `agents.max_subagents` 와 `budgets`(토큰/시간/loop)가 동시성·비용 상한. **무한 fan-out 금지.**
- 레인 worktree 는 변경 없으면 자동 정리, stale 은 PR squash-merge 시 prune.
- Workflow/에이전트 사용 자체를 **보드/이슈/PR/커밋 문구에 노출하지 않는다**(`messaging.md`).
- `/goal` 하드 가드(`engine-loop-and-goal.md` §3)는 Workflow 모드에서도 그대로 — fan-out 이 폭주를 못 만든다.
