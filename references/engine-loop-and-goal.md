# 엔진 — /loop + /goal 충실 재현 (engine-loop-and-goal) ★

이 스킬의 심장. 내장 `/loop`(자기 페이싱)와 `/goal`(정지 차단 게이트)의 **동작을 그대로 재현**해 결합한다.
`config.engine` 가 둘을 제어한다.

---

## 1. /loop — 자기 페이싱 엔진

내장 `/loop` 의 동작 계약:
- **인터벌 있음** → `CronCreate` 로 고정 간격 재실행, 첫 틱은 즉시.
- **인터벌 없음(기본)** → *동적 페이싱*: 지금 실행하고, 다음 반복을 **`ScheduleWakeup`** 로 스스로 페이싱.
- **멈추려면** 다음 `ScheduleWakeup`/`CronCreate` 호출을 **생략**한다(엔진은 "다음을 예약하지 않음"으로 종료).

ultraloop에서의 사용(매 loop ⑨ 종료 평가에서):

### 1-a. dynamic (기본·권장 — 장기 루프에 적합)
`config.engine.loop.pacing: dynamic`.

매 loop 끝에 다음을 판단해 **다음 깨어남**을 정한다:
- **외부 이벤트를 기다리는 중**(CI 워치, E2E 컨테이너 워밍업, 승인 큐 응답, nightly 결과 등)
  → **`Monitor`** 를 무장한다. 이벤트(예: CI 상태 변화, 승인 결과 파일 생성)가 오면 그때 깨어나 즉시 처리.
  Monitor의 필터는 **성공·실패 양쪽**을 잡아야 한다(크래시·행이 silence처럼 보이지 않도록).
- **특정 이벤트가 없고 그냥 다음 일감으로**
  → 곧장 다음 loop를 이어가거나(컨텍스트가 살아있으면), 잠깐 idle이면
  `ScheduleWakeup(delaySeconds=config.engine.loop.idle_wakeup_seconds, prompt="<같은 /ultraloop 입력>")`.
- **delay 고르기**(캐시 창 고려): 외부 상태를 적극 폴링하면 60~270s(캐시 유지), 분 단위로 바뀌는 걸
  기다리면 1200~1800s. 라운드 넘버(300s)는 피한다. `reason`은 구체적으로("watching CI for #123").

> ScheduleWakeup의 `prompt`에는 **이번 `/ultraloop` 입력을 그대로** 다시 넣어 다음 발화가 루프를 재진입하게 한다.

### 1-b. interval (고정 간격)
`config.engine.loop.pacing: interval`, `config.engine.loop.interval: "20m"` 등.

```
CronCreate(cron="<interval을 5필드 cron으로>", prompt="<같은 /ultraloop 입력>", recurring=true)
```
첫 틱은 즉시 실행(예약 후 바로 1회 돈다). 멈출 땐 `CronDelete`.

---

## 2. /goal — 정지 차단 게이트 (Stop 훅)

내장 `/goal <condition>` 의 동작 계약을 그대로 재현한다:
- 성공 **조건**을 설정한다(ultraloop에선 = DoD 또는 `config.engine.goal.condition`).
- **Stop 훅**: 에이전트가 정지를 시도할 때마다 조건을 **재검사**한다.
  - **충족** → goal clear, 정지 **허용**("목표 달성").
  - **미충족** → 정지 **차단**, `iteration`·`last_reason` **누적**, 계속 일하게 한다.
- 상태(조건·iteration·last_reason)는 상태 파일에 둔다.

### 2-a. 설치 (부트스트랩이 수행)
`config.engine.goal.install_stop_hook: true` 면 부트스트랩이 대상 레포 `.claude/settings.json` 의
`hooks.Stop` 에 다음을 등록한다(`assets/hooks/settings.snippet.json` 참조):

```json
{ "hooks": { "Stop": [ { "hooks": [ {
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/assets/hooks/goal-stop-gate.sh"
} ] } ] } }
```

`goal-stop-gate.sh` 는:
1. **하드 가드 먼저**(§3) — 상한 초과면 **정지 허용**(`exit 0`)하고 사유를 기록. *무한루프 차단이 최우선.*
2. `scripts/goal_check.sh` 로 DoD 충족 여부 평가.
3. **충족** → `exit 0`(정지 허용) + 상태에 `met` 기록.
4. **미충족** → stdout에 JSON `{"decision":"block","reason":"<남은 일/마지막 사유>"}` 출력(정지 차단) +
   `iteration++`, `last_reason` 갱신. 에이전트는 그 reason을 받아 계속 일한다.

> 이것이 "100% 될 때까지 안 멈춤"의 실제 엔진이다. `/goal` 의 met→clear, not-met→bump-and-continue 를 1:1 재현.

### 2-b. 조건
- `config.engine.goal.condition: "DoD"` (기본) → `references/definition-of-done.md` 전 항목 + 보드 全 Done +
  prod HITL 승인. `goal_check.sh` 가 이를 기계검증 가능한 부분(보드 카운트·CI·증거 파일 존재·HITL 상태)으로 평가.
- 자유 조건 문자열도 가능(예: `"all P0 items Done with E2E evidence"`).

---

## 3. ★ 하드 가드 (무한루프 금지 — 의무, 끌 수 없음)

가드 없는 Stop/SessionEnd 재투입은 폭주한다(과거 사고: 가드 0 훅이 2만 세션·토큰 폭발). 그래서 goal 게이트엔
다음이 **항상** 적용된다. 하나라도 걸리면 게이트는 **정지를 허용**하고 "미완 사유"를 보고한다.

| 가드 | 동작 |
|---|---|
| `config.engine.goal.max_iterations`(기본 200) | Stop 차단 누적이 상한 초과 → 정지 허용 + 에스컬레이션 |
| `config.engine.goal.lock_file` | 동시 재진입 잠금(stale 10분 청소). 잠겨 있으면 즉시 정지 허용(중복 게이트 방지) |
| `config.budgets`(loop/토큰/시간) | `cost_guard.sh` 가 초과 판정 → budget-stop(exit 7) → 게이트 정지 허용 |
| dead-man's-switch | N분 무진전(`budgets.dead_mans_switch_minutes`) → 알림 + 에스컬레이션 |

`goal-stop-gate.sh` 는 **goal_check 보다 가드를 먼저** 평가한다. *정지 차단은 가드를 통과했을 때만.*

> 추가 안전: Stop 훅이 띄우는 서브프로세스는 **`claude -p --bare`** 같은 재귀 호출을 하지 않는다
> (훅 안에서 새 세션을 만들지 마라). 게이트는 *판정만* 하고, 실제 작업은 메인 루프가 한다.

---

## 4. 둘의 결합 — 한 loop의 수명

```
[loop N]
  ① 계획 점검 (cost_guard·heartbeat·승인큐 drain)   ← 가드 상태 갱신
  ②~⑧ 레인 fan-out → merge → 보드 업데이트
  ⑨ 종료 평가:
       goal 충족? ──예──▶ ScheduleWakeup/Cron 생략 → 메인 루프 자연 종료
              │          (만약 에이전트가 일찍 멈추려 하면 Stop 훅이 다시 검사: 충족이면 통과)
              └─아니오─▶ /loop 페이싱으로 다음 깨어남 예약 (ScheduleWakeup 또는 Cron)
                          (만약 에이전트가 멈추려 하면 Stop 훅이 차단 + iteration++ + reason)
```

- **/loop** 는 *언제 다시 깨어날지*를, **/goal** 은 *멈춰도 되는지*를 책임진다. 둘은 직교한다.
- 정상 흐름에선 /loop 페이싱이 루프를 이어가고, /goal 훅은 "성급한 정지"를 막는 안전망으로 동작한다.
- 종료는 **goal 충족(정상)** 또는 **하드 가드(안전 정지)** 둘 중 하나로만 일어난다.

---

## 5. 운영 메모

- **시작**: 사용자가 `/ultraloop [repo]`. 부트스트랩 → roadmap_sync → loop. dynamic이면 첫 틱 즉시.
- **중단(사용자)**: 활성 cron은 `CronDelete`, dynamic은 다음 ScheduleWakeup 생략. goal 훅을 잠시 끄려면
  대상 레포 `.claude/settings.json`의 Stop 훅을 제거하거나 `config.engine.goal.enabled:false` 후 재부트스트랩.
- **재개**: 보드가 SoT라 어느 지점에서 끊겨도 `roadmap_sync`로 다시 그 지점부터(§REQ-ST-1).
- **관측**: `heartbeat.sh` 가 주기적 liveness를 Discord/상태파일에 남긴다(§observability).
