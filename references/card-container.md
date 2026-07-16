# Card = container — one card holds the whole work item (card-container) ★

The **v0.13 discipline**: a single board card (its backing issue) *is* the container for one unit of work — plan,
design link, progress, and evidence all converge on that one card. No parallel plan file, no scattered design doc,
no separate progress log. `pm` opens the card and states the problem; `loop` designs, plans, builds, and proves the
same card end to end. One card, one work item, one place to look.

## What the card carries

- **Issue BODY** — background + acceptance criteria + **Goal-link** (the milestone/north-star the card serves,
  `north-star.md`) + a **`## Implementation plan`** section written before the first Red commit (`card-planning.md`).
- **`Design-Doc` field** — the `artifacts.oliveeelab.com/<name>` URL of the card's single self-contained
  `imgyu-techdoc` HTML design doc, published via `artifacts-ops` (`dependencies.md §2`). The field holds the URL;
  the artifact holds the design.
- **Comments** — chronological progress + design decisions as the lane advances. The card's running log.
- **E2E evidence** — recorded in **two places, on purpose**:
  - **Canonical** = the repo file `e2e/reports/*.md`. `goal_check.sh` greps it for the `**PASS**`/`**FAIL**`
    markers (`e2e-production.md §3`), so this file is the machine gate and **must stay** — the mirror never replaces it.
  - **Mirror** = a human-readable **done-comment on the card**: a PASS/FAIL summary + a screenshot + a link back to
    the canonical report. So a person scanning the board sees the outcome without opening the repo.

## What lives where

| Layer | What | Where | Who |
|---|---|---|---|
| Frame | background · acceptance criteria · Goal-link | issue **body** | pm |
| Plan | `## Implementation plan` (file structure · tasks · interfaces) | issue **body** | loop |
| Design | single-file `imgyu-techdoc` HTML | `artifacts.oliveeelab.com` → **`Design-Doc` field** URL | design |
| Progress | chronological progress + design decisions | card **comments** | loop |
| Evidence (canonical) | `**PASS**`/`**FAIL**` markers, steps, transcripts | repo **`e2e/reports/*.md`** (goal gate) | loop |
| Evidence (mirror) | PASS/FAIL summary + screenshot + report link | card **done-comment** | loop |

## Sub-issue caution — design docs are NOT sub-issues

The hierarchy is a fixed **3-tier: Initiative → Epic → Task** (`gh-roadmap`, `dependencies.md §1`). A design doc is an
**artifact of a Task, not a child of it**. Filing the design as its own sub-issue would push the tree to 4 tiers and
break the roadmap layout. So the design doc lives on `artifacts.oliveeelab.com` and is **linked** from the card's
`Design-Doc` field — never nested under it as an issue.

## Why two SoTs would be wrong — and why the mirror is not one

The board card is the mutable SoT for state; `e2e/reports/*.md` is the canonical evidence the gate reads. The card
done-comment is a **read-only human mirror** of that evidence, not a second source — if the two ever disagree, the
repo report wins and the gate greps only the repo file. As everywhere: card/issue/PR/commit text stays human product
language, naming no tool or automation (`messaging.md`).
