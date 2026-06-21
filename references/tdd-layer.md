# Dynamic workflow + TDD (Tier 1) — tdd-layer

## 1. 동적 구성
이슈 성격에 맞춰 이번 사이클 워크플로를 짠다(비결정):
- **버그** → 재현하는 실패 테스트 먼저 → 수정 → 회귀 가드.
- **신규 기능** → 수용기준을 실패 테스트로 → 최소 구현 → 리팩터.
- **리팩터** → 회귀 테스트 그린 유지(before/after).

## 2. Red → Green → Refactor
각 단계 **실제 실행** + 원자 커밋. `test:` → `feat:`/`fix:` → `refactor:` 로 자연 분할.
**assertion/mock 은 Tier 1에서만**(빠르고 결정적). E2E를 assertion으로 위장하지 않는다(비목표).

## 3. 커버리지 & CI
- 커버리지 ≥ `config.coverage_target`(기본 80%). CI lint·type·test·build 녹색이어야 merge 진입.
- 스택별 명령은 `references/rules/{python,typescript,…}.md`. 있으면 프로젝트 스킬(`python-patterns`,
  `pytorch-patterns`, `fastapi-patterns`, `postgres-patterns` 등) 참조.

## 4. Tier 1 ≠ Tier 2
Tier 1(여기) = 단위/통합 테스트(assertion). Tier 2 = 실배포 후 사람처럼 구동하는 E2E(`e2e-production.md`).
**둘 다** 통과해야 merge. Tier 1 녹색만으로 Done 아님.
