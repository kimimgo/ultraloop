# Vendored: pre-mortem

Verbatim copy of the `pre-mortem` PM execution skill, **bundled so ultraloop ships
self-contained** — `pm` can risk-analyze a PRD or launch plan (Tigers / Paper Tigers /
Elephants → launch-blocking / fast-follow / track) without requiring the user to have the
upstream skill installed in `~/.claude` (same pattern as the bundled `imgyu-techdoc`).

- **Source**: `phuryn/pm-skills` : `pm-execution/skills/pre-mortem/SKILL.md`
- **Vendored**: 2026-07-15
- **sha256 at copy time**:
  - `SKILL.md` — `4e5cf10a46ac1d1cdde6aa009ba2b860c532f55c0c3d9ec53a82082cad073052`

**Re-sync policy**: this is a faithful mirror, not a fork. If the upstream skill changes,
re-copy the file and update this hash — do not diverge the vendored body.

## Adapt notes

The vendored body is unedited; these map its dangling references to ultraloop equivalents:

- **`$ARGUMENTS`** — upstream expects a slash-command argument. Here the skill is **invoked by
  `pm`**, which supplies the PRD / launch plan in context; read `$ARGUMENTS` as "the plan `pm`
  passes in", not a literal command arg.
