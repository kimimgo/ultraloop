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
   `Priority` (single-select P0/P1/P2). Also set the Status options to the execution columns you want (Backlog/Ready/In-Progress/In-Review/E2E/Done/Blocked/Parked).
   *(bootstrap does reinforce fields/Status, but having them in the template means cloning alone is enough.)*
3. **Views — 3 role-based views** (the most important part — impossible via the API): the standard is the 3 views actually configured
   on project #12 "imdental-ai roadmap". Layout is a means; each view's identity is **"who uses it to see what"**.
   - **Roadmap — PM · schedule view**: New view → Layout = **Roadmap**. Date field = `Target Date` (Start Date if needed).
     Group by `Horizon` (Long-term/Mid-term/Short-term). → A human PM plans and monitors the big picture of schedule, milestones,
     and versions. Project status updates (ON_TRACK/AT_RISK) also happen here.
   - **Dev Board view**: Layout = **Board**, Column by `Status`. Set Column limit (WIP), (optional) assignee filter.
     → Developer short-term execution.
   - **Build Monitor view**: Layout = **Table**, columns `Status` · `E2E-Evidence` · `Updated` · `Linked pull requests`.
     → Progress monitoring of the automated execution loop.
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
