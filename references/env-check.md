# 환경 구성 점검 — 매 loop ① (env-check)

매 loop 시작에서 두 가지를 점검한다(REQ-ENV-1).

## 1. 언어 룰팩 준수
- 스택 감지(`pyproject.toml`/`package.json`/`go.mod`/…) → 해당 룰 + `_base` 적용
  (`references/rules/{_base,readme,python,typescript,…}.md`).
- 점검: 린트/타입 설정 존재·통과, 디렉토리 레이아웃, **README 필수 섹션 + 단일 명령 기동**.
- 드리프트(룰 위반) → **교정 커밋** 또는 이슈 등록. README의 단일 명령 기동은 §9 E2E `up` 이 **그대로 실행**
  하므로 문서가 거짓이면 E2E가 깨진다 → 문서 환각 차단.

## 2. 직전 E2E 결과 평가
- 직전 loop의 E2E 리포트(`e2e/reports/`) 검토: 시나리오 커버리지 vs 로드맵 항목, 회귀, 미커버 영역.
- 미커버/약한 시나리오 → **보강 이슈** 생성. flake였던 항목은 원인 분류(`e2e-production.md` §flake).

## 3. 룰팩 위치
`references/rules/_base.md`(공통) + 언어별. 새 스택을 만나면 _base + 가장 가까운 언어 룰로 시작하고,
필요 시 그 스택 룰 파일을 보강(비결정 — 프로젝트가 가르쳐주는 대로).
