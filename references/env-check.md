# Environment & configuration check — every loop ① (env-check)

At the start of every loop, check two things (REQ-ENV-1).

## 1. Language rule-pack compliance
- Stack detection (`pyproject.toml`/`package.json`/`go.mod`/…) → apply that rule + `_base`
  (`references/rules/{_base,readme,python,typescript,…}.md`).
- Check: lint/type configs exist and pass, directory layout, **README required sections + single-command startup**.
- Drift (rule violation) → **correction commit** or file an issue. The README single-command startup is executed **as-is**
  by the §9 E2E `up`, so if the docs lie, E2E breaks → blocks documentation hallucination.

## 2. Evaluate the previous E2E results
- Review the previous loop's E2E reports (`e2e/reports/`): scenario coverage vs. roadmap items, regressions, uncovered areas.
- Uncovered / weak scenarios → create **reinforcement issues**. Items that flaked get root-cause classified (`e2e-production.md` §flake).

## 3. Rule-pack location
`references/rules/_base.md` (common) + per-language. When meeting a new stack, start with _base + the closest language rule,
and add a rule file for that stack if needed (non-deterministic — as the project teaches you).
