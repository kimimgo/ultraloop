# 알림 & 승인 — 비동기 큐 + 게이트웨이 봇 + 위험도 (notify-approval)

## 1. 비차단 알림 (REQ-NTF-1)
일상 이벤트(loop 시작/종료·push·CI·E2E 캡쳐·보드/로드맵 수정·heartbeat)는 Discord 알림 후 **진행**.
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh <level> "<title>" "<message>" [evidence_path]`. 알림 실패는 루프를
죽이지 않는다(notify.sh exit 0 항상). 로드맵 수정은 **notify-only + §9.7 diff/감사 로그**(REQ-NTF-2).

## 2. 비동기 승인 큐 (REQ-APR-1) — 결정
고위험(§14)은 **승인 큐에 enqueue + 해당 레인 Parked**, **나머지 레인/독립 작업은 계속**. 루프 미정지.
```bash
approval_queue.sh enqueue <action> <risk> [ttl]   # 큐 적재 + 레인 park
approval_queue.sh drain                            # ① 단계: 해결된 항목 unpark
```
큐는 파일 기반(`${TMPDIR:-/tmp}/ultraloop-approvals/`). exit 0=Y(진행) · 1=N(대안/이슈화) · 4=hold(TTL 무응답).

## 3. 수신 채널 — egress-only 호환 (REQ-APR-2)
- **Discord 게이트웨이 봇(아웃바운드 WebSocket)** 으로 **[Y]/[N] 버튼 + 사유** 수신 — 인바운드 인그레스 불필요
  (사내 DLP 호환). `scripts/approve_bot.py`(per-approval) 또는 `assets/discord/gateway-bot.example.py`(데몬).
- 보조: 봇 폴링, **콘솔 모달**(`console_modal.sh`, 유인 시).
- 응답: Y → unpark 진행 · N → 대안/이슈화.

## 4. hold-TTL 에스컬레이션 (REQ-APR-3)
큐 항목이 `config.discord.approval_ttl_minutes`(기본 120) 초과 무응답이면 **자동진행 금지**. 대신:
- **에스컬레이션**(반복 알림 격상), 그리고 가능하면 **defer**(해당 항목 후순위로 미루고 다른 항목 진행).
- 막판 모든 항목이 큐에 막히면 종료 평가에 **"승인 대기로 미완"** 명시(`definition-of-done.md`).

## 5. 프로덕션 배포 (REQ-APR-4)
**GitHub Environment 승인(권위)** + Discord 알림(대기 URL) 이중. `ci-cd-hitl.md` §5.

## 6. 감사 로그 (REQ-APR-5)
모든 알림/승인(채널·응답자·Y/N·사유·시각)을 보드 항목/감사 로그에 기록.

## 7. 위험도 분류 (§14)
- **고위험 = 큐+park** (REQ-RISK-1): 프로덕션 배포 · history rewrite · 데이터/볼륨 삭제(`down -v`(E2E 격리
  볼륨 제외)·db drop) · 대규모 파괴적 리팩터 · 의존성 **major** 업 · 시크릿/권한/결제 변경 ·
  미커밋/미머지 worktree 제거 · 외부 비가역 작업.
- **저위험 = 알림·진행** (REQ-RISK-2): 일반 커밋/푸시/PR/merge · 이슈·보드 업데이트 · 로드맵 수정 제안 ·
  테스트 추가 · 룰팩 교정 · 로컬 E2E 비파괴 기동/정리 · 문서.
- **모호하면 보수적 고위험**(careful, REQ-RISK-3).
