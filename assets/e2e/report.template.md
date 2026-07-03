# E2E report: {{date}} — {{item}}

> Record of actually running the scenario (scenario.template.md). The PR "## E2E evidence" section references this.
<!-- write instance prose in the product's working language -->

- **Linked issue**: #
- **Stack startup command**: <!-- the single README command verbatim. e.g. `docker compose -p <isolation-id> up -d` -->
- **Verification instance**: <!-- isolated port/identifier -->

## Per-step results
| # | Step | Result | Notes |
|---|------|------|------|
| 1 |  | PASS/FAIL |  |
| 2 |  | PASS/FAIL |  |

## Screenshots
<!-- Links or thumbnails only. No original embeds (each < 2MB). -->
- [step1]({{link}})

## Transcript
<!-- Path or link to console/network/CLI output logs. -->
-

## Health
<!-- Health check result after startup. e.g. GET /healthz → 200, container healthy -->
-

## Deterministic assertion results
| assertion | Expected | Actual | Result |
|-----------|------|------|------|
| HTTP status |  |  | PASS/FAIL |
| exit code |  |  | PASS/FAIL |
| DB row count |  |  | PASS/FAIL |

## Final result
**PASS** / **FAIL**
<!-- machine tokens: **PASS** / **FAIL** — never localize or restyle -->
<!-- If FAIL, apply the e2e:fail label and block merge. -->

## Evidence paths
<!-- Where this report and the screenshots/transcripts are stored. Record in the board E2E-Evidence field. -->
-
