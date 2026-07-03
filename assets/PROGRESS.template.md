<!-- ⚠️ This file is regenerated automatically from the board — do not edit directly.
     The SoT (Source of Truth) is the GitHub Projects board. This file is a read-only view built from the board by regen_progress.sh. -->
<!-- write instance prose in the product's working language -->

# Progress (regenerated view)

> Generated at: {{generated_at}} · loop {{loop_n}} / phase {{phase}}

## Lanes in progress
| Issue | Branch | Status | Owner |
|------|--------|------|------|
{{#lanes}}| #{{issue}} | {{branch}} | {{status}} | {{owner}} |
{{/lanes}}

## Board summary (count by status)
| Backlog | Ready | In-Progress | In-Review | E2E | Done | Blocked | Parked |
|---|---|---|---|---|---|---|---|
| {{backlog}} | {{ready}} | {{in_progress}} | {{in_review}} | {{e2e}} | {{done}} | {{blocked}} | {{parked}} |

## DoD checklist progress
{{dod_progress}}  <!-- e.g. 7/10 (70%) -->

## Recent E2E evidence
{{#e2e_recent}}- {{date}} · #{{issue}} · {{result}} · {{evidence_path}}
{{/e2e_recent}}

## Approval queue (HITL pending)
{{#approvals}}- #{{issue}} · {{reason}} · waiting {{waiting_for}}
{{/approvals}}

## Cost/time usage (vs budgets)
- Tokens/cost: {{cost_used}} / {{cost_budget}}
- Time: {{time_used}} / {{time_budget}}

## Last heartbeat
{{last_heartbeat}}

## Blockers
{{#blockers}}- #{{issue}} · {{detail}}
{{/blockers}}
