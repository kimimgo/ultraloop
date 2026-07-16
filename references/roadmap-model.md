# Roadmap model (roadmap-model) — GitHub Projects/Issues = the only mutable SoT

## 1. SoT = the GitHub Project (v2) board
The **only mutable source of state** for the roadmap is the Project v2 board. Fields (`assets/project-fields.json`):
- `Status`: Backlog / Ready / In-Progress / In-Review / E2E / Done / Blocked / **Parked**
- `Roadmap-Item(Epic)` · `Priority`(P0~P2) · `Size`(XS~XL) · `Depends-on` · **`E2E-Evidence`**(evidence path/URL)
- **`Design-Doc`**(per-card design-doc URL — the card's `imgyu-techdoc` HTML on `artifacts.oliveeelab.com`, `card-container.md`)

Hierarchy: **Roadmap-Item(Milestone/`epic:*`) ⊃ Issue(unit of work = card)**.

`PROGRESS.md` is a **read-only view** regenerated from the board (`regen_progress.sh`). Parallel lanes do not
write PROGRESS.md directly, so there is no contention or push conflict. Mutable state is written **only to the board**.

## 2. Standard conventions (bootstrap plants them)
Issue/PR templates (the PR has an **E2E evidence section**) · Conventional Commits · branch `type/<issue#>-<slug>` ·
labels (`assets/labels.json` — including the approval gate marker **`roadmap:approved`**) · **board automation requires a
project-scope PAT/App** (the default `GITHUB_TOKEN` cannot). Details in `git-and-issues.md`.

## 3. loop unit = orchestrator + parallel lanes
1 loop = organize the next N Ready issues into parallel lanes → each lane runs issue→TDD→push→CI→**pre-merge E2E**→
merge-ready → merge after join → board Done. (`loop-protocol.md`)

## 4. Idempotent board (query-then-create)
Board/field creation is **query by title first, create only when absent**. Record the created project node-id in
`config.roadmap.project_node_id` so that re-bootstrap **must not create duplicates**. Labels, fields, and options follow
the same pattern (`bootstrap_repo.sh`).

## 5. Precondition gate — roadmap required / planning proposal
Branch on the `roadmap_sync.sh` exit code:
- **exit 0 (exists + approved)** → enter the loop. "Approved" is confirmed via the issue label **`roadmap:approved`**
  (`assets/labels.json`, created by bootstrap). On the milestones fallback path, confirm via the `config.roadmap.approved=true` flag.
- **exit 3 (no roadmap)** → the loop does **not start → planning proposal mode**. Spec authority = **GitHub Spec Kit** (SKILL §4.1.3):
  1. **If the repo is new**, `gh repo create` → `bootstrap_repo.sh` (labels, board, `specs/` in place).
  2. Repo recon → **PM strategy stage (mandatory before Spec Kit, pm-skills vendored)**: `product-strategy` (strategy canvas) →
     `outcome-roadmap` (outcome roadmap — the check baseline for every loop) → **`strategy-red-team`** (assumption attack and
     kill-criteria adversarial validation — entering the Spec Kit stage without passing is forbidden; with N repos the meta runs it once at the platform level) →
     `specify init . --integration claude --script sh` (v0.10.x: installs the
     `.claude/skills/speckit-*` skills + the `.specify/` infra, not slash commands) → **Spec Kit chain**:
     `speckit-constitution → speckit-specify → speckit-clarify → speckit-plan → speckit-tasks →
     speckit-analyze`. The resulting spec stays in `specs/<NNN-feature>/` (the version-controlled original). A spec carries items +
     value + **acceptance criteria + E2E scenario candidates** + priority + dependencies.
  3. Ask the user for approval/edits (a legitimate block). Final authority over scope and priority belongs to the user.
  4. **Before writing the board**: validate issue priorities and Waves with `prioritization-frameworks` (RICE/ICE etc.). On approval →
     turn tasks into issues with `speckit-taskstoissues` (issue_populate.sh lock→ensure→unlock) → **after writing the board**:
     sweep the whole board once with `gstack-autoplan` (automated CEO/eng/DX review) to catch what is missing and what is excessive →
     link the board cards + grant the **`roadmap:approved` label** +
     **snapshot-freeze the acceptance criteria and scenarios** (§9.7 integrity baseline, `e2e-production.md`) → enter.
- **exit 5 (transient read failure: API/network)** → do **not** go to planning mode; retry/back off (prevents resetting an
  in-progress project to zero — REQ-RM-5). If it fails repeatedly, notify and wait.

> **Distinguishing absent vs temporarily unreadable is the crux.** One network drop must not get a healthy project reported
> as "no roadmap" and reset into planning mode. `roadmap_sync.sh` separates these two as exit 3 / exit 5.

## 5.1 Spec evolution policy (in-flight freeze / gate re-entry) — SKILL §4.1.4
A spec may change across loops (that is normal). But **modifying `specs/` mid-loop (in-flight) is forbidden** (§9.7 snapshot freeze).
When a change is needed: finish/park the in-progress lanes → **re-enter the gate** → incrementally revise only that feature spec
with Spec Kit (re-run `speckit-specify`) → user re-approval → re-freeze → turn **only the changed part** into issues via `speckit-taskstoissues`.
Duplicating existing issues is forbidden (§4 idempotent query-then-create). Since `specs/` lives in git, spec change history is tracked as well.
⚠️ Re-running `specify init` on a repo whose loop is in progress is forbidden — only at the point of (re-)entering the gate.

## 6. Fallback (when there is no PAT/App, R2)
Without a project-scope token, Projects v2 automation is impossible. Bootstrap **reports the failure explicitly** and falls back
to a **Milestone + label** based roadmap (board fields are approximated with labels/milestones). Record this fact in the PROGRESS view.
