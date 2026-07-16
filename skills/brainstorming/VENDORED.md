# Vendored: brainstorming

Verbatim copy of the `brainstorming` skill from obra/superpowers, **bundled so ultraloop ships
self-contained** — `pm` can explore user intent, requirements, and design before implementation
without requiring the user to have superpowers installed in `~/.claude` (same pattern as the
bundled `imgyu-techdoc`).

- **Source**: `obra/superpowers` : `skills/brainstorming/SKILL.md`
- **Vendored**: 2026-07-15
- **sha256 at copy time**:
  - `SKILL.md` — `e14914605f640e0841758e45d0ab2a53243b59b921f929e47921c99668f2e61d`

**Re-sync policy**: this is a faithful mirror, not a fork. If the upstream skill changes,
re-copy the file and update this hash — do not diverge the vendored body.

## Adapt notes

The vendored body is unedited; these map its dangling superpowers references to ultraloop
equivalents:

- **superpowers sub-skill refs** — the body's terminal state "invoke `writing-plans`" (and its
  siblings `subagent-driven-development` / `executing-plans`) are superpowers skills that do not
  exist here. In ultraloop, the hand-off from a validated design is instead **`lane-fanout` /
  `milestone-fanout`** (parallel execution) planned via **`card-planning.md`**. Read "invoke
  writing-plans" as "hand the validated design to ultraloop's planning + fan-out path".
- **`docs/superpowers/…` paths** — the body writes/reads the design spec under
  `docs/superpowers/specs/…`. In ultraloop the design artifact lives on **the card** (see
  `card-container.md`), not that filesystem path.
- **`$ARGUMENTS` / slash-command framing** — the skill is **invoked by `pm`**, which supplies
  the topic in context rather than as a literal command arg.
