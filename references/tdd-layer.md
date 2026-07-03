# Dynamic workflow + TDD (Tier 1) — tdd-layer

## 1. Dynamic composition
Shape this cycle's workflow to the nature of the issue (non-deterministic):
- **Bug** → a reproducing failing test first → fix → regression guard.
- **New feature** → acceptance criteria as failing tests → minimal implementation → refactor.
- **Refactor** → keep regression tests green (before/after).

## 2. Red → Green → Refactor
Each stage is **actually executed** + committed atomically. Split naturally as `test:` → `feat:`/`fix:` → `refactor:`.
**Assertions/mocks belong to Tier 1 only** (fast and deterministic). Do not disguise E2E as assertions (non-goal).

## 3. Coverage & CI
- Coverage ≥ `config.coverage_target` (default 80%). CI lint·type·test·build must be green to enter merge.
- Per-stack commands are in `references/rules/{python,typescript,…}.md`. If present, consult the project skills
  (`python-patterns`, `pytorch-patterns`, `fastapi-patterns`, `postgres-patterns`, etc.).

## 3.5 ★ Rulepack gates (per lane · 4 gates before merge — enforce the highest per-language/stack standard)
After Green, at Refactor close-out, run the 4 gates below **inside the lane**; all must be green before push→CI.
Do not skip them in the lane trusting CI re-verification alone (delayed feedback = lane waste). Commands come from
`config.stack.*` when set; when empty, detect the stack and use the defaults below (details/exceptions in `references/rules/<language>.md`):

| Gate | python | typescript/node | go | rust |
|---|---|---|---|---|
| ① format | `ruff format --check .` | `prettier --check .` | `gofmt -l .` (output 0) | `cargo fmt --check` |
| ② lint | `ruff check .` | `eslint .` | `go vet ./...` | `cargo clippy -- -D warnings` |
| ③ type | `mypy .` (or pyright) | `tsc --noEmit` | (covered by compilation) | (covered by compilation) |
| ④ test+cov | `pytest --cov` ≥ target | `vitest run --coverage` ≥ target | `go test -cover ./...` ≥ target | `cargo test` (+tarpaulin) |

- **Coverage is judged per card** — if the coverage of the modules this card touched is below target, that lane is barred
  from merge (no hiding in the overall average).
- A gate failure = same rank as Red: fix and re-run. 3 consecutive failures of the same gate → lane Parked + approval queue (no infinite retries).
- For unknown stacks, follow the `rules/_base.md` principles (compose the 4 kinds — formatter·linter·type/compile·test — from that ecosystem's standards).

## 4. Tier 1 ≠ Tier 2
Tier 1 (here) = unit/integration tests (assertions). Tier 2 = E2E driven like a human after a real deploy (`e2e-production.md`).
**Both** must pass for merge. Tier 1 green alone is not Done.
