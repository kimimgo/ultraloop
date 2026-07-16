# Vendored: imgyu-techdoc

Verbatim copy of the `imgyu-techdoc` technical-document harness, **bundled so ultraloop ships
self-contained**. `loop` authors each card's design doc as a single self-contained HTML in this
house style without requiring the user to have `imgyu-techdoc` installed in `~/.claude`
(same pattern as the bundled `gh-roadmap`).

- **Source**: `~/.claude/skills/imgyu-techdoc` (author's harness)
- **Vendored**: 2026-07-15
- **sha256 at copy time**:
  - `SKILL.md` — `38dd7d4eafe0d9c664cd9dddf04b5e1aceadcef968d0b1a1378318690b69d471`
  - `reference/template.html` — `7d243c4eb1ab01807b7825249e2628a2d85b55abfb494c0be9d6ef97a2665648`
  - `reference/style-and-tone.md` — `f5d0c22753de92f58c732455c71b54d38d0e03298bd3b013915998a7f4e255ff`
  - `reference/diagrams.md` — `f783bdcf109be0612a99494da8f6cde03db5b886ba6c2eb0f888c1169550a546`

**Re-sync policy**: this is a faithful mirror, not a fork. If the source harness changes,
re-copy the files and update these hashes — do not diverge the vendored copy, so the design-doc
house style stays consistent everywhere.

**Used by**: `loop` for per-card design docs (v0.13 M3/M4). The generated single-file HTML is
published via `artifacts-ops` to `artifacts.oliveeelab.com/<name>` and linked from the card's
`Design-Doc` field.
