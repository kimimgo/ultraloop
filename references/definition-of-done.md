# 완료 정의 (definition-of-done) — 루프의 종료 조건 + 무결성

> 아래 **전 항목**이 *검증 가능한 증거*(CI 링크·E2E 캡쳐·보드 상태·수치)와 함께 ✅ 이고, **최종 프로덕션
> 배포가 HITL 승인·성공**해야 완료다. 하나라도 의심·미충족이면 루프 계속(/goal 게이트가 정지 차단).
> mission/로드맵이 도메인별 항목을 **추가**한다(아래는 공통 기준선). `goal_check.sh` 가 이를 평가한다.

## 전역 DoD 체크리스트
- [ ] 보드 전 항목 **Done** (Backlog/Ready/In-Progress/In-Review/E2E/Blocked/Parked = 0)
- [ ] 각 Roadmap-Item이 **merge 전 프로덕션 E2E**를 캡쳐 증거와 함께 통과(`E2E-Evidence` 필드 채워짐)
- [ ] 유저 타입별 시나리오 × E2E 전부 PASS(웹 클릭/CLI 셸/API 실호출 — `e2e-production.md`)
- [ ] 엣지케이스 헌팅 ≥1라운드, 발견 항목 전부 해결 또는 이슈 트래킹
- [ ] CI 녹색(lint/typecheck/test/build) — 봇 QA 게이트 통과
- [ ] 테스트 커버리지 ≥ `config.coverage_target`(기본 80%)
- [ ] **단일 명령 기동** 가능(README ↔ E2E up 계약 일치, 룰팩 `references/rules/*` 준수)
- [ ] CD 실증: `merge → staging 자동배포 → 스모크 → production HITL 승인 → 배포`
- [ ] 보안/시크릿: 평문 시크릿 0, `.env.e2e`/Secrets만, 자격증명 수명 점검(`observability.md`)
- [ ] **추적성**: 모든 머지가 PR 경유, 모든 PR이 이슈를 닫음, `blocked` 0, `PROGRESS.md` 뷰 최신
- [ ] **무결성(§9.7)**: 수용기준 스냅샷 대비 범위 축소/시나리오 약화가 감사 로그에 기록·정당화됨
- [ ] 최종 프로덕션 배포 **HITL 승인·성공**(헬스 OK)

## §9.7 완료 무결성 (notify-only 유지 + 비차단 안전장치)
완료 판정에 에이전트 자기 판단이 포함되므로(self-grading), 골대 이동을 *사후에 보이게* 한다:
1. **수용기준 동결** — 기획 승인 시 항목별 수용기준·E2E 시나리오를 불변 기준선으로 저장(`roadmap-model.md` §5).
2. **수정 diff 알림 + 감사 로그** — 에이전트의 로드맵/시나리오 수정은 승인 불요(notify-only)지만, 기준선 대비
   diff를 Discord 알림 + 감사 로그에 남긴다. **범위 축소/시나리오 약화는 명시**(차단 X, 가시성 O).
3. **결정적 assertion 병행** — E2E 판정은 관찰 + 기계검증(HTTP 상태·DB 행수·파일 존재·exit code)을 병행해
   자기판단 단독 합격을 줄인다.

## 안전 정지(미완) 보고
§15 하드 가드(loop/토큰/시간 상한·승인 대기 적체)에 닿으면 게이트는 정지를 허용하고 **미완 사유를 명시**한다:
"100%까지 무한"을 금지(REQ-ST-4). 막판 모든 항목이 승인 큐에 막히면 "승인 대기로 미완"을 보고.

## 완료 보고 형식 (전 항목 ✅ + 프로덕션 HITL 승인 시에만 출력)
```
## ✅ ULTRALOOP 완료 보고
- 미션 요약 / 최종 릴리즈 태그:
- 보드: 전 항목 Done (총 N개, Epic M개)
- DoD 항목별 결과 + 증거 링크:
- 항목별 E2E 증거 경로(캡쳐 <2MB, merge commit trailer/보드 필드):
- 시나리오·E2E 결과(웹/CLI/API + 결정적 assertion):
- 엣지케이스 처리:
- CI/CD + 프로덕션 배포(HITL 승인자/시각/버전/헬스):
- 무결성: 수용기준 스냅샷 대비 수정 내역(범위 축소 있었으면 사유):
- 비용/시간 사용량(budgets 대비):
- 잔여 리스크 / 후속 권고 · 클린 환경 재현 절차:
```
