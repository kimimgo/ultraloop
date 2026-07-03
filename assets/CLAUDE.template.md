# CLAUDE.md

> This repo is driven by **ultraloop** (an autonomous engineering loop).
> The SoT for progress state is the GitHub Projects board. `PROGRESS.md` is a read-only view regenerated from the board — do not edit it directly.

## Core contract

- **Issues first**: every piece of work starts from an issue (card) on the board. No changes without an issue.
- **Atomic commits**: one commit = one logical change. Message `type: summary (#issue)`, written in the product's working language. Commit only in a build/test-passing state.
- **TDD**: new features/bugs get tests first. Coverage target is `coverage_target` (default 80).
- **E2E before merge**: a PR merges only with E2E PASS evidence. Screenshots as links/thumbnails (<2MB), alongside deterministic assertions.
- **Traceability**: changed lines ↔ issue ↔ PR (`Closes #`) must stay linked.
- **Single-command startup**: the whole stack must come up with the single command in the README, and E2E `up` calls that command as-is.
- **No secret commits**: committing `.env`/keys/tokens is forbidden. Examples go in `.env.example`.

## Rulepacks

Per-stack quality standards (lint/type/layout/README) follow the ultraloop rulepacks:
`${CLAUDE_PLUGIN_ROOT}/references/rules/` (`_base.md` + the detected stack rules).
