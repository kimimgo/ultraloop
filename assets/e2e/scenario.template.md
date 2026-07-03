# E2E scenario: {{item}}

> Verify "end to end" from the user's perspective. Put observable evidence and **deterministic assertions** side by side (SPEC §9.7).
<!-- write instance prose in the product's working language -->

## Item
<!-- Which feature/flow this verifies. Linked issue #number. -->

## User type
<!-- Anonymous / logged-in user / admin etc. -->

## Preconditions (seed)
<!-- Data/state needed. Which seed script creates it. Startup follows the single README command (up). -->
-

## Steps
<!-- Clicks / shell / HTTP requests etc. Deterministically reproducible. -->
1.
2.
3.

## Expected observations (evidence + deterministic assertions together)
<!-- Write observation evidence like screenshots/DOM together with machine-verified deterministic assertions. -->
- Screenshot/DOM: <!-- what must be visible -->
- HTTP status: <!-- e.g. GET /orders/1 → 200 -->
- exit code: <!-- e.g. CLI command exit code 0 -->
- DB row count: <!-- e.g. SELECT count(*) FROM orders → 1 -->

## PASS criteria
<!-- PASS when all observations/assertions above are met. Any single mismatch is FAIL → label e2e:fail. -->
-
