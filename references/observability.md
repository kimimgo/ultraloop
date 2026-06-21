# 관측성 · 비용/시간 상한 · 자격증명 수명 (observability)

## 1. heartbeat + dead-man's-switch (REQ-ST-3)
- **heartbeat**: 주기적 liveness를 Discord/상태파일에. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/heartbeat.sh` —
  매 loop ①에서 호출. 상태파일 `${TMPDIR:-/tmp}/ultraloop/heartbeat`에 타임스탬프 기록
  (= `heartbeat.sh`의 `$STATE_DIR/heartbeat`; `cost_guard.sh`의 dead-man 검사가 같은 파일을 읽음).
- **dead-man's-switch**: 마지막 진전(커밋/카드 이동/heartbeat) 이후 `config.budgets.dead_mans_switch_minutes`
  (기본 30) 초과면 알림 — 멈춤·행을 외부에서 감지.

## 2. 비용/시간 상한 (REQ-ST-4) — budget-stop
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/cost_guard.sh` — 매 loop ①에서 호출. `config.budgets` 점검:
- `max_loops`(0=무제한, 단 goal.max_iterations가 상한) · `max_wall_clock_hours`(기본 24) ·
  `max_tokens`(0=세션한도) · `ci_minutes_per_day`.
- 초과 시 **exit 7(budget-stop)** → goal 게이트가 정지 허용 + 요약 알림("100%까지" 무한 방지).

> cost_guard·goal 게이트·dead-man 은 한 묶음의 안전망이다. 어느 하나가 상한을 알리면 루프는 **안전 정지**하고
> `definition-of-done.md` 의 "미완 사유"로 보고한다.

## 3. 자격증명 수명 (REQ-ST-5)
git/PAT/봇 토큰 만료를 **사전 점검·갱신**. 부트스트랩 + 매 loop ①에서 `gh auth status`,
project-scope 토큰(`config.roadmap.token_env`), Discord 봇 토큰(`config.discord.token_env`)의 유효성/만료 임박을
확인. 만료 임박 시 알림 — 무인 중 silent auth 실패 방지.

## 4. 상태 단일화 · 재개 (REQ-ST-1)
가변 SoT = 보드. PROGRESS.md = 재생성 뷰. 재개 시 보드를 읽어 그 지점부터(화해 규칙 불요).

## 5. 안전 레일 (REQ-ST-6)
E2E 배포 = 로컬·일회성(프로덕션 부수효과 0). 시크릿은 env/Secrets만. 장시간/병렬 잡 타임아웃·리소스 상한.
보호·HITL 우회 금지. 파괴적 작업은 `notify-approval.md` §7 / 승인 큐.

## 6. 무한루프 방지 메모(중요)
관측성 스크립트(heartbeat/cost_guard)와 goal Stop 훅은 **새 claude 세션을 재귀 생성하지 않는다**. 훅·가드는
*판정/알림만* 하고 실제 작업은 메인 루프가 한다. (가드 없는 훅 재투입은 폭주 — `engine-loop-and-goal.md` §3.)
