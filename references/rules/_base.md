# Rulepack base (common to all stacks)

> This is not law but a **default guide**. Adapt it sensibly per project.
> When the stack is detected at every loop ① → apply the matching language rules (`python.md`, `typescript.md`, ...) together with this `_base.md`.
> Rulepack location: `${CLAUDE_PLUGIN_ROOT}/references/rules/`

## How the rulepack is applied

1. **Detect**: at loop start, look at the repo root. `pyproject.toml` → python, `package.json` + `tsconfig.json` → typescript, etc. If several, start from the primary stack.
2. **Apply**: make `_base` + the detected stack rules the quality bar of that loop.
3. **Drift correction**: when the rules and the current code diverge — small differences become a **correction commit** inside that work; large ones are split off as a separate **issue** (label `chore`/`refactor`). Do not mix unrelated cleanup into one PR.

## Single-command startup (the E2E `up` contract)

This is the most important common contract. A repo must come up with **one command**.

- e.g. `docker compose up -d`, `make up`, `./scripts/dev.sh`.
- This command must be written **verbatim** in the README's "single-command install & run" section.
- The `up` stage of the E2E runner (`e2e.runner`) calls that command from the README **verbatim**. A separate procedure written elsewhere is not allowed — this is the device that blocks documentation hallucination.
- After startup, a health check (HTTP 200, containers healthy, etc.) must be able to confirm it is "up".

If docs and reality diverge (README says `make up` but it does not actually run) → that itself is a defect. Fix the code or the docs so they match.

## Secrets

- Secrets are **never committed**. `.env`, keys, tokens, certificates.
- Provide examples via `.env.example` (values empty/dummy), and put the real `.env` in `.gitignore`.
- Read configuration from environment variables (no hardcoding in code). Keep the variable list in the README "Configuration (env)" section.
- If an already-committed secret is discovered → raise a `security`-labeled issue immediately and state that rotation is required.

## .gitignore hygiene

- Ignore build artifacts, caches, virtualenvs, logs, `.env`, IDE settings, and raw E2E evidence (large files like screenshots).
- Do not put raw E2E evidence in the repo — use links/artifacts. Details in the PR template (`< 2MB`, no embeds).

## Atomic commits

- One commit = one logical change. Commit in a state where build/tests pass.
- The message is `type: summary` (type uses the same vocabulary as labels: feat/fix/test/refactor/chore/docs). Reference `(#issue)` when possible.
- Do not mix unrelated changes into one commit.

## Test directory layout

- Tests live in a separate `tests/` (or the stack-conventional location). Do not mix them with source.
- Separate by kind: `tests/unit/`, `tests/integration/`, `tests/e2e/` (or `e2e/` for scenarios/reports).
- The coverage target is `coverage_target` (default 80). Write tests first so new code holds this line (TDD).
