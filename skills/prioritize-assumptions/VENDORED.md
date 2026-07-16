# Vendored: prioritize-assumptions

Verbatim copy of the `prioritize-assumptions` PM product-discovery skill, **bundled so
ultraloop ships self-contained** — `pm` can triage assumptions on an Impact × Risk matrix and
propose experiments without requiring the user to have the upstream skill installed in
`~/.claude` (same pattern as the bundled `imgyu-techdoc`).

- **Source**: `phuryn/pm-skills` : `pm-product-discovery/skills/prioritize-assumptions/SKILL.md`
- **Vendored**: 2026-07-15
- **sha256 at copy time**:
  - `SKILL.md` — `18160a0138c788790c9dd22995ffdcfac485c1f0599c170d8668678e59766073`

**Re-sync policy**: this is a faithful mirror, not a fork. If the upstream skill changes,
re-copy the file and update this hash — do not diverge the vendored body.

## Adapt notes

The vendored body is unedited; these map its dangling references to ultraloop equivalents:

- **`$ARGUMENTS`** — upstream expects a slash-command argument. Here the skill is **invoked by
  `pm`**, which supplies the assumption list in context (typically the output of
  `identify-assumptions`); read `$ARGUMENTS` as "the assumptions `pm` passes in", not a literal
  command arg.
