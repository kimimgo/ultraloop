# {{PROJECT_NAME}} — roadmap board

> {{ONE_LINE — what this product is and why it exists, in one sentence.}}

## North star

**{{NORTH_STAR_SENTENCE — the single measurable end-state this board drives toward.}}**

| Metrics (≤3) | Anti-goals (≤3 — what we deliberately do NOT build) |
|---|---|
| {{METRIC_1}} | {{ANTI_GOAL_1}} |
| {{METRIC_2}} | {{ANTI_GOAL_2}} |
| {{METRIC_3}} | {{ANTI_GOAL_3}} |

## Milestone map

| Milestone | Goal (one sentence) | Verdict question at close | Key cards |
|---|---|---|---|
| {{M1_TITLE}} | {{M1_GOAL}} | {{M1_VERDICT_Q}} | {{#issue links}} |
| {{M2_TITLE}} | {{M2_GOAL}} | {{M2_VERDICT_Q}} | {{#issue links}} |

## How to read this board

- **Roadmap — PM · Schedule** — the big schedule picture: milestones on a timeline by Horizon and Target Date.
- **Dev Board** — execution kanban by Status (`Backlog → Ready → In-Progress → In-Review → E2E → Done`, plus `Blocked`/`Parked`).
- **Build Monitor** — grouped by `Wave`: what is being built in parallel right now.
- **Card Audit** — one row per card: `Design-Doc` · `Stage` · `E2E-Evidence` · `Status` — a card's whole life at a glance.

**Every card is a container.** The issue body holds the background, acceptance criteria, and the implementation plan;
the `Design-Doc` field links the card's design document; progress and decisions are chronological comments;
E2E evidence lives in the repository (`e2e/reports/`) with a summary mirrored on the card.

## Working agreements

- `Ready` means the card has a goal link and checkable acceptance criteria — nothing enters work without them.
- `Done` means merged with passing end-to-end evidence, not "code written".
- Direction is reviewed once, after the first vertical slice ships; after that, work proceeds autonomously to the milestone boundary.
- Dependencies are tracked as `blocked-by` relations; blocked cards carry the reason as a comment.

## Links

- Repository: {{REPO_URL}}
- Staging / production: {{ENV_URLS_OR_N/A}}
- Design documents: {{DESIGN_DOC_HOST_OR_"linked per card via the Design-Doc field"}}
