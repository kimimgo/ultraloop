# Golden template setup (human, once · then clone forever)

Views (Roadmap layout · WIP · group/filter), Insights, and built-in workflows **cannot be created via the API** (verified). Instead,
use the **template** of GitHub official best practice #8: a human configures one golden template board in the UI → bootstrap
clones it wholesale into every project with `copyProjectV2`. What `copyProjectV2` carries over (verified against official docs):
**views · custom fields · draft issues · workflows (except auto-add) · Insights**. What it does not carry: items, collaborators, **team/repo links**
(→ bootstrap relinks with `linkProjectV2ToRepository`, so no problem).

## A. Building the golden template (once, UI)

Full checklist: `assets/template-spec.md`.

1. **Create the board** — github.com → your user/org → Projects → New project. Title example: `Roadmap Template`.
2. **Custom fields** (Settings → Fields): `Horizon` (single-select: Long-term/Mid-term/Short-term) · `Target Date` (date) ·
   `Priority` (single-select P0/P1/P2) · `Design-Doc` (text) · `Stage` (single-select: Planning/Designing/Building) ·
   `Wave` (number). Also set the Status options to the execution columns you want (Backlog/Ready/In-Progress/In-Review/E2E/Done/Blocked/Parked).
   *(bootstrap does reinforce fields/Status, but having them in the template means cloning alone is enough.)*
   ⚠️ **Field prerequisites**: the target views below reference `Design-Doc`, `Stage`, and `Wave`, so these fields must
   exist on the template **before** you build the views — a view cannot group/column by or show a field that isn't there yet.
3. **Views — 4 target views** (the most important part — impossible via the API): the golden template board
   (kimimgo/projects/1, node `PVT_kwHOAUMds84BQdkb`; fields are already provisioned via `board.sh ensure-fields`)
   must be built with the 4 views below. Layout is a means; each view's identity is **"who uses it to see what"**.
   The fresh board opens with one default "View 1" (Table) — rename it into view ① rather than deleting it.
   - ① **Roadmap — PM · Schedule**: rename View 1 → click the view's ▾ → Layout = **Roadmap**.
     In the view settings: Dates = `Start Date` → `Target Date` (draws duration bars; Target alone gives dots),
     Group by = `Horizon`, Zoom = Month. Markers: enable Milestones. Sort: `Target Date` ascending.
     → A human PM plans and monitors the big schedule picture. Status updates (ON_TRACK/AT_RISK) also happen here.
   - ② **Dev Board**: New view → Layout = **Board**. Column by = `Status` (columns appear in option order:
     Backlog → Ready → In-Progress → In-Review → E2E → Done → Blocked → Parked). Card preview fields: show
     `Priority` · `Size` · `Stage`. Optional: column limit (WIP) on In-Progress ≈ `worktree.max_lanes`.
     → Developer short-term execution.
   - ③ **Build Monitor**: New view → Layout = **Table**. Group by = `Wave` (⚠️ Board columns only take
     single-select/iteration fields — `Wave` is NUMBER, so Table-with-grouping is the reliable form).
     Visible fields: Title · `Status` · `Stage` · `Design-Doc`. Filter: `-status:Done,Parked` (active work only).
     → Each Wave group = one parallel batch; what runs concurrently right now is visible at a glance.
   - ④ **Card Audit**: New view → Layout = **Table**. Visible fields: Title · `Status` · `Stage` · `Design-Doc` ·
     `E2E-Evidence` · `Priority` · Milestone. Group by = Milestone, Sort = `Status`.
     → A card's whole life (design → stage → evidence) in one row; the per-card audit the container discipline promises.
4. **Built-in workflows** (Settings → Workflows): turn on "Item closed → Done" and "Pull request merged → Done".
   *(These are off on API-created boards — verified. With them on, closing moves items to Done automatically.)*
5. **Insights** (optional): Insights → configure charts (burndown / distribution by Horizon etc.). They come along with the clone (verification/reading not possible).
6. **Get the node id**: `gh api graphql -f query='query($l:String!){ repositoryOwner(login:$l){ ... on User
   { projectsV2(first:50){ nodes{ id title } } } } }' -f l=<owner>` → record the `id` matching the template title into config
   `board.template_node_id`. ⚠️ `markProjectV2AsTemplate` is **org only** (not for user accounts, verified) —
   but `copyProjectV2` clones any board without the marker, so **the marker is unnecessary**.

## B. Clone (automatic)

```bash
# config: after recording the golden template id in board.template_node_id
bash ${CLAUDE_SKILL_DIR}/scripts/roadmap_bootstrap.sh
#  → with template_node_id, copyProjectV2 (clones views·Insights·workflows) · without, fresh create (no views/Insights)
bash ${CLAUDE_SKILL_DIR}/scripts/roadmap_view.sh check   # check ROADMAP_LAYOUT · workflows enabled
```

## C. The auto-add gap (the only thing the template cannot clone)

To auto-add new issues to the board, place the `assets/add-to-project.yml` workflow in the repo (`actions/add-to-project`).
Put a PAT (repo+project scopes) in a repo secret. In an ultraloop environment keep `runs-on: self-hosted`.
*(Or configure the auto-add workflow manually in the UI after bootstrap — but per repo.)*

## D. Without a template (fresh board)

Bootstrap works without a golden template too: board, fields, hierarchy, dependencies, status updates, multi-repo — all fine.
**The only things missing are the roadmap layout view, Insights, and built-in workflow enablement** (`roadmap_view.sh check` warns).
Fresh for prototypes; the golden template is recommended for real operation.
