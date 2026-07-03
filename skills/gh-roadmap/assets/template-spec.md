# Golden template board — configuration checklist

What the golden template that `roadmap_bootstrap.sh` clones with `copyProjectV2` must contain. A human configures it once in the UI.
Procedure: `references/golden-template-setup.md`.

## Fields
- [ ] **Status** (single-select) — execution columns: Backlog · Ready · In-Progress · In-Review · E2E · Done · Blocked · Parked
      *(bootstrap also aligns them to config.status_options, but having them in the template means cloning alone is enough)*
- [ ] **Horizon** (single-select) — Long-term · Mid-term · Short-term  *(3-tier group/filter)*
- [ ] **Target Date** (date) — end of the Roadmap bar (target date)
- [ ] **Priority** (single-select) — P0 · P1 · P2  *(optional)*
- [ ] **Iteration** (iteration) — weeks/velocity  *(optional; not simply creatable via the API, so define it here)*
- Native auto fields (no setup needed): Milestone · Parent issue · Sub-issues progress · Assignees · Labels

## Views — 3 role-based views (★ not creatable via the API — must be included in the template)

The standard is the **role-based 3 views** actually configured on project #12 "imdental-ai roadmap". Layout is a means;
each view's identity is **"who uses it to see what"**.

- [ ] **Roadmap — PM · schedule** view — Layout=**Roadmap** · Date field=**Target Date** (Start Date if needed) ·
      **Group by Horizon** (Long-term/Mid-term/Short-term)
      *(purpose = a human PM plans and monitors the big picture of schedule, milestones, and versions. Project status updates
      ON_TRACK/AT_RISK also happen here.)*
- [ ] **Dev Board** view — Layout=**Board** · **Column by Status** · set **Column limit (WIP)** ·
      (optional) assignee filter
      *(purpose = developer short-term execution.)*
- [ ] **Build Monitor** view — Layout=**Table** · columns **Status · E2E-Evidence · Updated · Linked pull requests**
      *(purpose = progress monitoring of the automated execution loop.)*

## Built-in workflows (Settings → Workflows)
- [ ] Turn on **Item closed → Done**  *(off on API-created boards — verified)*
- [ ] Turn on **Pull request merged → Done**
- [ ] (auto-add is not cloned → `assets/add-to-project.yml` or per-repo UI configuration)

## Insights (optional, comes along with the clone)
- [ ] Burndown/velocity charts · distribution by Horizon etc.  *(reading/verification via the API not possible; clone only)*

## Wrap-up
- [ ] Template board node id → config `board.template_node_id`
- [ ] (optional · **org only**) `markProjectV2AsTemplate` — not possible for user accounts, but copyProjectV2 clones without the marker, so it does not matter
