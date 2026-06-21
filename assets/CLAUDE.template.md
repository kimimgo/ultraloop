# CLAUDE.md

> 이 레포는 **ultraloop**(자율 엔지니어링 루프)로 구동된다.
> 진행 상태의 SoT는 GitHub Projects 보드다. `PROGRESS.md`는 보드에서 재생성되는 읽기전용 뷰이니 직접 편집하지 말 것.

## 핵심 규약

- **이슈 우선**: 모든 작업은 보드의 이슈(카드)에서 시작한다. 이슈 없는 변경 금지.
- **원자 커밋**: 한 커밋 = 하나의 논리적 변경. 메시지 `type: 요약 (#이슈)`. 빌드/테스트 통과 상태로 커밋.
- **TDD**: 신규 기능/버그는 테스트 먼저. 커버리지 목표는 `coverage_target`(기본 80).
- **merge 전 E2E**: PR은 E2E PASS 증거가 있어야 merge. 스크린샷은 링크/썸네일(<2MB), 결정적 assertion 병행.
- **추적성**: 변경 라인 ↔ 이슈 ↔ PR(`Closes #`)이 연결돼야 한다.
- **단일 명령 기동**: 전체 스택은 README의 단일 명령으로 떠야 하고, E2E `up`이 그 명령을 그대로 부른다.
- **시크릿 미커밋**: `.env`/키/토큰 커밋 금지. 예시는 `.env.example`.

## 룰팩

스택별 품질 기준(lint/type/레이아웃/README)은 ultraloop 룰팩을 따른다:
`${CLAUDE_PLUGIN_ROOT}/references/rules/` (`_base.md` + 감지된 스택 룰).
