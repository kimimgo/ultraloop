<!-- ⚠️ 이 파일은 보드에서 자동 재생성됨 — 직접 편집 금지.
     SoT(Source of Truth)는 GitHub Projects 보드다. 이 파일은 regen_progress.sh가 보드에서 만든 읽기전용 뷰. -->

# 진행 현황 (재생성 뷰)

> 생성 시각: {{generated_at}} · loop {{loop_n}} / phase {{phase}}

## 진행 중인 레인
| 이슈 | 브랜치 | 상태 | 담당 |
|------|--------|------|------|
{{#lanes}}| #{{issue}} | {{branch}} | {{status}} | {{owner}} |
{{/lanes}}

## 보드 요약 (상태별 카운트)
| Backlog | Ready | In-Progress | In-Review | E2E | Done | Blocked | Parked |
|---|---|---|---|---|---|---|---|
| {{backlog}} | {{ready}} | {{in_progress}} | {{in_review}} | {{e2e}} | {{done}} | {{blocked}} | {{parked}} |

## DoD 체크리스트 진행률
{{dod_progress}}  <!-- 예: 7/10 (70%) -->

## E2E 증거 최근 항목
{{#e2e_recent}}- {{date}} · #{{issue}} · {{result}} · {{evidence_path}}
{{/e2e_recent}}

## 승인 큐 (대기 중 HITL)
{{#approvals}}- #{{issue}} · {{reason}} · 대기 {{waiting_for}}
{{/approvals}}

## 비용/시간 사용량 (budgets 대비)
- 토큰/비용: {{cost_used}} / {{cost_budget}}
- 시간: {{time_used}} / {{time_budget}}

## 마지막 heartbeat
{{last_heartbeat}}

## 블로커
{{#blockers}}- #{{issue}} · {{detail}}
{{/blockers}}
