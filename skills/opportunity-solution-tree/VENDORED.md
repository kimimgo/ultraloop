# Vendored: opportunity-solution-tree

Verbatim copy of the `opportunity-solution-tree` PM product-discovery skill, **bundled so
ultraloop ships self-contained** — `pm` can structure discovery (outcome → opportunities →
solutions → experiments) without requiring the user to have the upstream skill installed in
`~/.claude` (same pattern as the bundled `imgyu-techdoc`).

- **Source**: `phuryn/pm-skills` : `pm-product-discovery/skills/opportunity-solution-tree/SKILL.md`
- **Vendored**: 2026-07-15
- **sha256 at copy time**:
  - `SKILL.md` — `6b23e44a5ace86aa20d64cc130322265ace6a53a29831cc403b974098a379bcc`

**Re-sync policy**: this is a faithful mirror, not a fork. If the upstream skill changes,
re-copy the file and update this hash — do not diverge the vendored body.

## Adapt notes

The vendored body is unedited; these map its dangling references to ultraloop equivalents:

- **`$ARGUMENTS`** — upstream expects a slash-command argument. Here the skill is **invoked by
  `pm`**, which supplies the outcome / mission in context; read `$ARGUMENTS` as "the target
  outcome `pm` passes in", not a literal command arg.
