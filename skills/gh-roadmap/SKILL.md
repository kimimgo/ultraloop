---
name: gh-roadmap
description: >-
  GitHub Projects (v2) board-based roadmap manager — builds a long/mid/short-term
  (Initiative→Epic→Task) 3-tier using GitHub official best-practice mechanisms verbatim:
  native sub-issue hierarchy, native issue dependencies (blocked-by), Roadmap layout view +
  Target Date, one shared board across multiple repos, native project status updates
  (On track/At risk), milestone wiring. The board is the single source of truth. Items that
  cannot be 'created' via the API — views, Insights, built-in workflows — are automated by
  cloning a human-built golden template with copyProjectV2, and the auto-add gap is filled
  with actions/add-to-project. USE THIS when the user wants "로드맵 관리", "프로젝트 보드",
  "장기/중기/단기 로드맵", "GitHub Projects 로 로드맵", "이슈 계층/sub-issue", "이슈 의존성
  보드", "멀티레포 프로젝트 보드", "로드맵 마일스톤", "roadmap board", "project v2 로드맵" —
  and when a higher-level loop such as ultraloop needs board structure/setup. For creating a
  single issue the gh CLI is enough (this is for board roadmap structure).
---

# gh-roadmap — GitHub Projects board roadmap (long/mid/short-term)

Operate a GitHub Projects (v2) board as a 3-tier roadmap **exactly per the official best practices**. The board is the **single mutable source of truth (SoT)**. One shared board across multiple repos is the default assumption (for a single repo, put just one entry in `repos`).

> `${CLAUDE_SKILL_DIR}` = this skill directory. Read `references/*.md` when details are needed (progressive disclosure).

---

## 0. Core model — 3-tier (structure ⊥ due dates, separated)

| Horizon | Structure (hierarchy, **native sub-issues**, cross-repo OK) | Due dates (time) |
|---|---|---|
| **Long-term** Initiative (quarter/year) | Top-level issue | Roadmap view bar (`Target Date`) |
| **Mid-term** Epic (month/sprint) | **Sub-issue** of the long-term item | **Milestone** (per-repo due date + progress %) / Iteration |
| **Short-term** Task (day/week) | **Sub-issue** of the mid-term item | Milestone assignment + `Status` column |

- **Hierarchy = native sub-issues** (`addSubIssue`) — automatically reflected on the board as the `Parent issue` / `Sub-issues progress` fields.
- **Dependencies = native blocked-by** (`addBlockedBy`) — regardless of repo boundaries. No title-regex or TEXT-field workarounds.
- **Timeline = Roadmap layout view + `Target Date`** + Horizon single-select (Long-term/Mid-term/Short-term) group/filter.
- **Multi-repo = one shared board** + N-repo `linkProjectV2ToRepository`. ⚠️ **Milestones are repo-scoped** (no cross-repo)
  → the cross-repo timeline SoT is the board `Target Date`/Iteration; milestones are per-repo due-date buckets (auto-synced).
- **Health = native status updates** (`createProjectV2StatusUpdate`: ON_TRACK/AT_RISK/...).

Which official best practice each element maps to: **`references/best-practice-mapping.md`**.

---

## 1. ⚠️ API-automatable vs template-only boundary (must understand)

This boundary was verified against the live GraphQL schema. **The only limit of unattended automation is 'views'**.

| Item | Direct API creation | Automation path |
|---|---|---|
| Fields · issue hierarchy · dependencies · status updates · board · repo links | ✅ mutations exist | scripts do it directly |
| **Views** (Roadmap layout · WIP · group/filter) | ❌ no create mutation | **golden template → copyProjectV2 clone** |
| **Built-in workflows** (closed→Done etc.) | ❌ no create/update (delete only) | template clone (except auto-add) · verify by `reading` only |
| **Insights/charts** | ❌ no type in the schema | golden template clone only (not even verifiable) |
| auto-add (the only thing the template cannot clone) | ❌ | **`actions/add-to-project`** (`assets/add-to-project.yml`) |

> Bottom line: **a human builds one golden template board in the UI** (Roadmap view · Insights · workflows) → bootstrap
> clones it into every project with `copyProjectV2`. Setup: **`references/golden-template-setup.md`**.
> It works without a golden template too (fresh board) but **there is no roadmap view / Insights** (fields, hierarchy, dependencies are fine).

---

## 2. Quick start

```bash
cp ${CLAUDE_SKILL_DIR}/config.example.yaml ./gh-roadmap.config.yaml
# fill board.title / board.owner / repos / (optional) board.template_node_id

bash ${CLAUDE_SKILL_DIR}/scripts/roadmap_bootstrap.sh         # board query-then-create (or template clone) + N-repo link + fields + Status alignment
#   → record the printed project_node_id/number into the config (idempotency key)
bash ${CLAUDE_SKILL_DIR}/scripts/roadmap_view.sh check        # verify view/workflow/field setup (warns if the roadmap view is missing)

# create 3-tier items (long-term → mid-term (parent=long-term) → short-term (parent=mid-term, cross-repo OK))
bash .../roadmap_item.sh <owner/repo> Long-term "User auth platform" --date 2026-12-31 --milestone "v1.0"
bash .../roadmap_item.sh <owner/repo> Mid-term "OAuth2 login"    --parent <long-term-url> --date 2026-09-30
bash .../roadmap_item.sh <owner/repo2> Short-term "Callback handler"      --parent <mid-term-url> --status Ready

bash .../roadmap_dep.sh add <blocked-url> <blocking-url>      # native dependency
bash .../roadmap_status.sh set ON_TRACK "Wave 0 in progress" --target 2026-12-31   # board health
```

---

## 3. Script map

| Script | Role |
|---|---|
| `roadmap_bootstrap.sh` | Shared board query-then-create **or golden template copyProjectV2 clone** · N-repo link · custom fields (Horizon/**Start Date**/Target Date/Priority) · **Status option alignment** (fresh board Todo→config, fixes the ultraloop trap) · **auto-records project_node_id/number into the config via sed** (hardened 2026-06-21). Idempotent. |
| `roadmap_item.sh` | Roadmap item creation = issue + board add + Horizon/Date/Status + **sub-issue hierarchy** (`--parent`) + **milestone** (`--milestone`, ensure-then-assign). |
| `roadmap_dep.sh` | Native dependencies `add`/`rm`/`list` (blocked-by). |
| `roadmap_view.sh` | `check` — **reads** the views (ROADMAP_LAYOUT present or not) · workflows (enabled) · fields to **verify the setup**. Lets an unattended skill self-check that the golden template was applied. |
| `roadmap_status.sh` | Native project status updates `set`/`list` (ON_TRACK/AT_RISK/OFF_TRACK/COMPLETE/INACTIVE). |
| `_lib.sh` | Shared helpers (cfg_get·gq·owner/issue/repo node·add_item·set_field). All graphql (gh version agnostic). |

Assets: `assets/fields.json` (field definitions) · `assets/add-to-project.yml` (auto-add workflow) · `assets/template-spec.md` (golden template checklist).

### ⚠️ Operational traps (field-verified 2026-06-21)
- **Config location = working repo root.** `ghr_config_path` searches for `gh-roadmap.config.yaml` from cwd upward. A config created in a different directory (e.g. a parent repo) is not found from a child repo cwd, so `roadmap_item.sh` fails with **exit 3 (board.project_node_id not set)**. → Put the config at the root of the repo that uses the board (bootstrap now auto-records the node_id).
- **stdin clash in bulk issue-creation loops.** Calling `gh issue create` inside `while read … done <<< "$DATA"` lets gh swallow the loop stdin and break it → **`</dev/null`** is mandatory on gh calls. (Same for `gh issue view`/`gh api`.)
- **The shell may be zsh.** `mapfile` and some bash-only syntax are missing → save multi-iteration loop scripts to a file and run with **`bash script.sh`**.
- **Labels must be full names.** If the `type` value is `feat`, use `--label "type:feat"` (prefix included). Without the prefix, create fails because the label does not exist.
- **If Roadmap bars are empty**, fill both Start Date + Target Date, connect them in the UI 'Set date fields', and Group by `Milestone` (see api-cheatsheet).

---

## 4. ultraloop wiring (this skill is the 'structure/setup authority'; ultraloop is the 'consumer')

ultraloop **consumes** the board (reads Ready cards and builds). **The authority for board structure/setup is this skill** — no two SoTs.

- ultraloop **planning gate (§4)**: use `roadmap_bootstrap.sh` when board creation, fields, or multi-repo links are needed,
  `roadmap_item.sh` to create roadmap items as 3-tier, and `roadmap_dep.sh` for dependencies (native instead of title regex).
- ultraloop **N-repo (§5.5)**: bootstrap the shared board with this skill. ultraloop `board.sh`/`roadmap_sync.sh` keep
  handling **read/card-move consumption** (no duplicate implementation).
- The ultraloop `ready_status` trap: this skill's bootstrap aligns the Status options to the config, so `Ready` really exists
  even on a fresh board.

Detailed wiring: `references/best-practice-mapping.md` §wiring.

---

## Appendix — verification history (provenance)

- **2026-06-13 — full-feature live E2E verification (E2E-VERIFIED).** With 2 disposable repos (`kimimgo/ghr-e2e-a|b`) + a disposable
  board: bootstrap (board creation · linking both repos · 3 fields · Status alignment Todo→config) → 3-tier item creation (long-term in
  repo-a ⊃ mid-term in repo-a ⊃ **short-term in repo-b = cross-repo sub-issue**) → milestone ensure+assign → blocked-by
  dependency add/list → project status ON_TRACK → view check (warning that ROADMAP_LAYOUT is absent · 6 workflows enabled
  state · native Parent issue/Sub-issues progress/Milestone fields confirmed) — all externally verified. Board/temporaries deleted afterwards.
  - **Key verified facts**: ① Default Status options can be replaced via `updateProjectV2Field` → eliminates the fresh-board ready_status
    trap at the source. ② **A board created via the API has no ROADMAP_LAYOUT view and the closed→Done workflow is off**
    (unlike UI-created boards) → for the roadmap view · Insights · workflows, golden template copyProjectV2 is the answer. ③ Cross-repo
    sub-issues work. ④ Native Milestone/Parent issue/Sub-issues progress fields exist on the board automatically.
  - **Bugs fixed**: syntax error from `\"` escapes inside `python3 -c` f-strings → replaced with the env+heredoc pattern
    (dep/view/status). Repo creation flags absent on apt gh 2.4.0 → the scripts use graphql only, so unaffected (verified).
