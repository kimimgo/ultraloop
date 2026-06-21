# 프로덕션 E2E (Tier 2) — merge 전 게이트 + 캡쳐 + 무결성 (e2e-production) ★

Tier 1 assertion ≠ E2E. **Roadmap-Item·PR은 merge 전** Tier 2 통과 + 캡쳐 증거 없이는 Done/merge 불가.
스크립트: `e2e_up.sh` → `e2e_run.sh` → `e2e_down.sh`. merge 게이트는 `ship_pr.sh`(E2E 실패 시 exit 6).

## 1. up — 실배포, 레인 격리 (REQ-E2E-2)
- `docker compose -p ue-<issue#> up`(우선) 또는 README **단일 명령 기동**(`runner: readme_command`).
- **레인 격리**: 고유 compose project-name(`ue-<issue#>`) + **동적 포트 할당**(`config.e2e.base_port`부터) +
  볼륨 격리 → 병렬 충돌 방지. 헬스 대기(`health_timeout_seconds`) → 시드.
- 자격증명은 `.env.e2e`(`config.e2e.secrets_file`)에서 주입(§5).

## 2. run — 실제 구동, mock 금지 (REQ-E2E-3)
사람처럼 구동해 관찰한다:
- **웹 UI** = 브라우저 자동화 MCP 에이전트 주도(클릭/입력 + **스크린샷 + DOM 판독**, 관찰 기반).
- **CLI/TUI** = **별도 셸 세션**에서 명령 시나리오(트랜스크립트 + exit code + 산출물).
- **API** = 실제 HTTP + 스키마/부수효과 검증.
- (필요 시) **수치** = 실솔버 수렴 + 허용오차.
시나리오 템플릿 `assets/e2e/scenario.template.md`.

## 3. 캡쳐 증거 + DLP (REQ-E2E-4)
- `e2e/reports/<date>-<item>.md` 에 스텝·스크린샷·트랜스크립트·헬스·PASS/FAIL(`assets/e2e/report.template.md`).
- **스크린샷은 압축/다운스케일해 파일당 < `config.e2e.screenshot_max_mb`(기본 2MB)**, 보고서엔 **링크/썸네일**
  (원본 임베드 금지 — 사내 DLP).
- 증거 경로를 **merge commit trailer + 보드 `E2E-Evidence` 필드**에 기록(squash 후에도 추적).

## 4. 시크릿 주입 (REQ-E2E-5)
E2E 스택 자격증명 = `.env.e2e`(로컬 vault/GH Secrets에서 주입). **평문 커밋 금지**, teardown 시 폐기.

## 5. flake 처리 (REQ-E2E-6)
실배포 E2E는 flaky하다. **일시 실패(포트·타임아웃·컨테이너 워밍업) = 백오프 재시도(≤ `config.e2e.flake_retries`,
기본 3)**. 재시도 후에도 실패해야 **결정적 실패**로 보고 + strike. **flake는 strike 아님**(허위 에스컬레이션 방지).
`e2e_run.sh` 가 일시/결정적 실패를 분류해 재시도한다.

## 6. down — 누수 방지 (REQ-E2E-7)
레인 종료 시 `compose -p ue-<issue#> down -v`(§14 가드: `down -v` 볼륨 삭제는 고위험 → E2E 일회성 격리
볼륨에 한해 허용) + **고아 컨테이너/볼륨/포트 회수**. **디스크 watchdog**: 임계 초과 시 `docker system prune`
+ 알림(`e2e_down.sh`).

## 7. 페이싱 (REQ-E2E-8)
무거운 E2E는 loop 내 **로컬**, CI는 **경량 스모크**, 전체 회귀는 **nightly**(`assets/workflows/nightly-e2e.yml`).

## §9.7 완료 무결성 안전장치 (비차단)
- **수용기준 스냅샷 동결**: 기획 승인 시 항목별 수용기준·E2E 시나리오를 불변 기준선으로 저장.
- **수정 diff 알림 + 감사 로그**: 에이전트의 시나리오 수정은 notify-only지만 기준선 대비 diff를 알림/감사.
  **범위 축소/시나리오 약화는 명시**(차단 X, 가시성 O).
- **결정적 assertion 병행**: 관찰 + 기계검증(HTTP 상태·DB 행수·파일 존재·exit code)을 함께 — 자기판단 단독 합격 축소.
