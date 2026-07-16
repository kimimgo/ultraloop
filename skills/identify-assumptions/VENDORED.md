# Vendored: identify-assumptions

Copy of the `identify-assumptions-new` PM product-discovery skill, **bundled so ultraloop ships
self-contained** — `pm` can map a new idea's risky assumptions across the 8 risk categories without the user
having the upstream skill installed in `~/.claude` (same pattern as the bundled `imgyu-techdoc`).

- **Source**: `phuryn/pm-skills` : `pm-product-discovery/skills/identify-assumptions-new/SKILL.md`
- **Vendored**: 2026-07-15
- **sha256 (current, after the one local edit below)**:
  - `SKILL.md` — `fb07720c17616a16819811a56c2b94851276422e72e1e057d82f36a81bc4bdf3`

**Local edit — the ONLY deviation from verbatim**: the frontmatter `name:` was changed from the upstream
`identify-assumptions-new` to **`identify-assumptions`**, so it matches this directory and the exact name `pm`
calls it by (the 1% rule invokes by name). The body is otherwise unedited.

**Re-sync policy**: faithful mirror, not a fork. If the upstream skill changes, re-copy the file, **re-apply the
`name:` rename to `identify-assumptions`** (or every `identify-assumptions` invocation breaks), and update the
sha256 above.

## Adapt notes (dangling refs → ultraloop equivalents; body unedited)

- **`$ARGUMENTS`** — upstream expects a slash-command argument. Here the skill is **invoked by `pm`**, which
  supplies the new-product idea in context; read `$ARGUMENTS` as "the idea `pm` passes in", not a literal command arg.
