<!-- PR template. One PR = one issue. -->
<!-- write instance prose in the product's working language -->

Closes #<!-- issue number -->

## Summary of changes
<!-- What changed and why. Every changed line must be traceable to the issue above. -->

## E2E evidence
<!-- Required. Pre-merge E2E must be PASS. Detailed format: assets/e2e/report.template.md -->

- **Stack startup command**: <!-- the single command from the README, verbatim. e.g. `docker compose up -d` (started as an isolated instance) -->
- **Scenario**: <!-- the user scenario item that was verified -->
- **Health**: <!-- health check result. e.g. GET /healthz → 200, container healthy -->
- **Deterministic assertions**: <!-- results such as HTTP status / exit code / DOM / DB row count -->
- **Screenshots/transcript**: <!-- link or thumbnail. No full-size embeds (each < 2MB) -->
- **Evidence path**: <!-- e2e/reports/... path -->
- **Result**: PASS / FAIL

## Checklist
- [ ] Tests green (unit/integration/e2e)
- [ ] Coverage >= target (`coverage_target`, default 80)
- [ ] Rulepack compliance (lint/type/layout/README)
- [ ] Traceability: changed lines ↔ issue linked, `Closes #` stated
- [ ] E2E PASS (evidence above attached)
- [ ] No secrets committed, `.gitignore` sane
