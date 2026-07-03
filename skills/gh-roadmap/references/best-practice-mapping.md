# best-practice mapping — GitHub official Projects best practices ↔ gh-roadmap mechanisms

Source: GitHub Docs "Best practices for Projects" (BP#1~#10). Each mechanism was verified for automatability against
the live GraphQL schema (2026-06-13).

## Mapping table

| GitHub official BP (verbatim) | gh-roadmap mechanism | API / path | verbatim? |
|---|---|---|---|
| BP#2 *"multiple levels of sub-issues"* (hierarchy) | Long-term ⊃ Mid-term ⊃ Short-term = multi-level sub-issues | `addSubIssue` ✅ | ✅ |
| BP#2 *"blocked by, or blocking"* (dependencies) | native blocked-by | `addBlockedBy`/`removeBlockedBy` ✅ | ✅ |
| BP#2 *"Milestones ... track how smaller issues fit into the larger goal"* | mid-term due-date bucket | `gh api repos/.../milestones` + native sync ✅ | ✅ |
| BP#4 *"roadmap layouts ... manage roadmaps"* | Roadmap layout view | ❌ no create mutation → template copyProjectV2 | ✅ |
| BP#5 *"Date field for target ship dates"* | `Target Date` field | `createProjectV2Field` DATE ✅ | ✅ |
| BP#5 *"Single select field for priority/phase"* | `Horizon` (Long-term/Mid-term/Short-term) · `Priority` | `createProjectV2Field` SINGLE_SELECT ✅ | ✅ |
| BP#5 *"Iteration field ... velocity planning"* | Iteration (optional) | template/UI (ITERATION special setup) | ✅ |
| BP#3 *"status updates ... On track / At risk"* | project status updates | `createProjectV2StatusUpdate` ✅ | ✅ |
| BP#6 *"Automate ... item closed → Done, auto-add"* | built-in workflows | ❌ no create/update (delete only) → template; auto-add = `actions/add-to-project` | ✅ |
| BP#7 *"Insights ... charts"* | Insights | ❌ no API type → template copyProjectV2 only | ✅ |
| BP#8 *"project templates"* | golden template clone | `copyProjectV2` (clones views·fields·workflows (except auto-add)·Insights) ✅ | ✅ |
| BP#9 *"link projects to ... repositories"* | one shared board across multiple repos | `linkProjectV2ToRepository` ✅ | ✅ |
| BP#10 *"single source of truth"* | board = the single mutable SoT | issue meta (assignee/milestone/label) auto-sync ✅ | ✅ |

> The **naming** "long/mid/short-term" is not GitHub wording; it is a standard application of the GitHub "multiple levels
> of sub-issues" mechanism to horizons (the mechanisms themselves are all official BP).

## API-automatable vs template-only (verified boundary)

- **Direct mutation available**: createProjectV2 · copyProjectV2 · createProjectV2Field · updateProjectV2Field
  (including Status option replacement) · updateProjectV2ItemFieldValue · addProjectV2ItemById · linkProjectV2ToRepository ·
  addSubIssue · addBlockedBy · createProjectV2StatusUpdate · markProjectV2AsTemplate (⚠️ org only — not for user
  accounts; copyProjectV2 clones any board without the marker, so it does not matter).
- **No direct mutation (read only/template only)**: **views** (views{layout,filter,groupBy,sortBy} read only — the `ROADMAP_LAYOUT`
  enum exists but cannot be created) · **workflows** (workflows{name,enabled} read + delete only; no create/update) ·
  **Insights** (no type in the schema at all — not even readable).
- **Verified traps**: ① A fresh board created via the API has no ROADMAP_LAYOUT view and the closed→Done workflow is off
  (unlike UI-created boards). → For the roadmap view/Insights/workflows, **golden template copyProjectV2** is the answer
  (`golden-template-setup.md`). ② The default board Status is Todo/In Progress/Done → bootstrap aligns it to the config.

## Wiring — ultraloop (consumer) boundary

- **This skill = roadmap structure/setup authority** (board creation·fields·hierarchy·dependencies·multi-repo links·status updates).
- **ultraloop = board consumer** (reads Ready cards and builds; `board.sh`·`roadmap_sync.sh`·`meta_sync.sh` do read/card-move).
- No two SoTs: one board is the single mutable state. ultraloop **references** this skill in the planning gate / N-repo bootstrap,
  and for dependencies progressively adopts `roadmap_dep.sh` (native blocked-by) instead of title regex.
- ✅ **ultraloop integration complete (2026-06-13)**: the ultraloop `meta_sync.sh assign` gate queries the title leading code +
  `depends_on:` body **and gh-roadmap native blocked-by, both** (a blocker must be CLOSED to satisfy the gate;
  `meta_sync.sh self-test` 4/4). The two dependency models coexist — ultraloop worker assignment respects gh-roadmap native
  dependencies as-is (`blockedBy(first:20){ nodes{ number state } }` added to the `meta_sync.sh` query).
- ultraloop wiring points: SKILL.md §4.1.2 (board structure/setup) · §5.1 planning gate skill table · §5.5 N-repo bootstrap.
