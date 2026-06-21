# 커밋/푸시/PR 메시지 — 한국어 (messaging)

## 1. 제목 결정적 / 본문 한국어 (REQ-MSG-1)
- `type(scope): <제목>` — **type·scope·제목은 결정적 템플릿**. changelog/semver/보드 자동화가 안정적으로
  파싱하려면 제목이 흔들리면 안 된다.
- **본문(왜/무엇)만 LLM 한국어**(비결정). 발산 원인·해법·트레이드오프를 자연스러운 한국어로.

## 2. 한국어 writing 스킬 런타임 탐지
`compose_msg.sh` 가 `~/.claude/skills/humanize-korean` 또는 `stop-slop` 존재를 감지.
있으면 본문을 그 스킬로 다듬고, 없으면 인라인 한국어로. **템플릿 박제 금지**(본문 한정 — 제목은 템플릿 유지).

## 3. 예시
- `fix(solver): cavity 입구 BC 수정`
  본문: "입구 경계조건이 압력 발산을 유발 → 속도 고정으로 교체. 100스텝까지 residual 1e-6 수렴 확인."
- `feat(api): 주문 생성 엔드포인트 추가`
  본문: "장바구니→주문 전이를 트랜잭션으로 묶어 부분 실패 방지. E2E에서 결제 우회 provider로 완결 검증."

## 4. 사용
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/compose_msg.sh commit "<scope>" "<무엇을 왜>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/compose_msg.sh pr     "<요약>" "<변경/E2E 결과>"
```
PR 본문은 `assets/pr_template.md`(E2E 증거 섹션 포함)를 채운다. 알림 메시지 본문도 같은 톤.

## 5. ★ 외부 가시 텍스트에 도구·자동화 정체 비노출 (REQ-MSG-2)
보드 카드·이슈 코멘트·PR·커밋처럼 **협업자/외부가 읽는 모든 문구**는 제품·프로젝트 언어로만 쓴다. 사람이
직접 작업한 것으로 읽혀야 한다.
- **금지 토큰**: `ultraloop`·스킬명(`pm`/`loop`)·"자율/자동 루프"·"에이전트"·"오케스트레이터"·"레인(lane)"·
  `ue-`/`ul-` 접두사 등 도구·내부 메커니즘 흔적.
- **치환 예**: "eng 자동 루프 제외" → "개발 작업 큐와 구분(기획/탐색 단계)" · "레인 ue-12에서 처리" → 작업
  내용만 서술 · "에이전트가 머지" → "머지 완료".
- 이미 노출했으면 `gh issue comment <n> --edit-last`(또는 PR/커밋 amend)로 중립 표현 정정.
- 내부 운영 신호(레인 ID·세션명·워커 식별자)가 필요하면 **보드 밖**(로컬 `PROGRESS.md` 뷰·로그)에만 둔다.
- 근거·재발 사례 = `references/failure-modes.md` FM14.
