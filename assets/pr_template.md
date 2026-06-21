<!-- PR 템플릿. 한 PR = 한 이슈. -->

Closes #<!-- 이슈 번호 -->

## 변경 요약
<!-- 무엇을, 왜 바꿨는지. 변경한 라인은 모두 위 이슈로 추적 가능해야 한다. -->

## E2E 증거
<!-- 필수. merge 전 E2E가 PASS여야 한다. 자세한 형식은 assets/e2e/report.template.md -->

- **스택 기동 명령**: <!-- README의 단일 명령 그대로. 예: `docker compose up -d` (격리 인스턴스로 기동) -->
- **시나리오**: <!-- 검증한 사용자 시나리오 항목 -->
- **헬스**: <!-- 헬스 체크 결과. 예: GET /healthz → 200, 컨테이너 healthy -->
- **결정적 assertion**: <!-- HTTP status / exit code / DOM / DB 행수 등 결과 -->
- **스크린샷/트랜스크립트**: <!-- 링크 또는 썸네일. 원본 임베드 금지(각 < 2MB) -->
- **증거 경로**: <!-- e2e/reports/... 경로 -->
- **결과**: PASS / FAIL

## 체크리스트
- [ ] 테스트 녹색 (unit/integration/e2e)
- [ ] 커버리지 >= 목표(`coverage_target`, 기본 80)
- [ ] 룰팩 준수 (lint/type/레이아웃/README)
- [ ] 추적성: 변경 라인 ↔ 이슈 연결, `Closes #` 명시
- [ ] E2E PASS (위 증거 첨부)
- [ ] 시크릿 미커밋, `.gitignore` 위생
