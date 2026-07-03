# N-repo orchestration (multi repo / 1 shared board / session-manager workers) — meta layer

> The worker spawn backend (session manager) and the message broker are **optional per-environment integrations**. The default behavior is tmux + send-keys; an external session manager/broker is used when present, with graceful fallback when absent.

> Trigger condition: `config.repos:` has **2 or more** entries. With 1 or fewer, ignore this document — the existing single-repo loop stands as is.
> Measured prototype: a 3-part topology of multi-repo + shared board + session-manager workers (validated on a real multi-repo topology). This document is its generalization.

## 1. Two-layer structure — who does what

```
meta (host cc, the one reading this skill) ── owns the 1 shared board · assigns issues→repos · gates cross Depends-on
   │                                · spawns/observes workers · throttles usage · meta /loop·/goal
   └─ session manager/tmux ──▶ N repo workers (tmux cc sessions) = the existing single-repo ultraloop as is,
                    except ① they do not create their own board (board.shared=true) and ② they read the shared board filtered to their own repo.
```

- **Two tiers of parallelism**: across repos (N workers) × within a repo (M worktree lanes, existing model unchanged).
- **Worker = reuse of the existing loop.** The only new thing is the thin meta layer. A worker never doubles as the meta.
- The difference from in-process Agent lanes = **a human can attach with `ta <repo>` to observe and intervene** (the reason this structure exists).

## 2. SSOT — 1 board / N repos linked

- The board is **one shared board above the repos** (`board.shared: true`). Creating a board per repo is forbidden (the existing §2
  board bootstrap skips only the board-creation part in N-repo mode; `board_bootstrap.sh` does it instead).
- Fields: the existing `Status`/`Depends-on`/`E2E-Evidence`/`Priority`/`Size` + **`Repository` (built-in — the worker assignment key)** +
  **`Stage` (custom single-select — the build stage cutting across repos)**.
- **Cross-repo Depends-on (★ only the meta knows)**: if a repo A issue depends on a repo B issue, that is expressed only in the board `Depends-on`.
  The meta enforces it — **until the predecessor card is Done, the successor issue is not sent down to that worker's Ready.**
  Workers do not know about cross dependencies (designed so they never need to).
- Reporting = not chat but **card state + issue comments + E2E-Evidence** (SSOT unification). State lives in GitHub, control in
  the session manager/tmux, observation in capture-pane + the board — a 3-way separation.
- The `PROGRESS.md` view is regenerated in the **hub repo** (where specs/ lives) as two tiers: per-repo sections + a global rollup.

## 3. Board operations — native `gh project` first, graphql as the version-agnostic fallback

`gh project` is the standard command of modern gh (≥2.31). **Check the gh version first** — an old version (e.g. Ubuntu apt's
2.4.0/2022) lacks the command, and then upgrading is the proper fix (official release binary → `~/.local/bin`; if a leftover
apt old version shadows it on PATH, remove it with `sudo apt remove gh`). `roadmap_sync.sh` checks availability at
runtime and **falls back automatically**, so it works either way. `board_bootstrap.sh` is graphql-based (version-agnostic, idempotent).
The token requires the `project` scope (`roadmap.token_env`). Canonical graphql snippet:

```bash
# Read items (including Repository·Status) — shared by worker filtering and meta assignment
gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { items(first:100){ nodes {
  content{ ... on Issue { number title repository{ nameWithOwner } } }
  fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue {
    name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' -f id="$PROJECT_NODE_ID"
# Create/link/Stage field = scripts/board_bootstrap.sh (idempotent query-then-create)
```

`roadmap_sync.sh` falls back to this graphql path automatically when `gh project` is absent, and when `board.shared=true`
filters to its own repo's (`repo:`) cards only. In shared-board mode the approval verdict is read from `roadmap.approved`
(written into the worker config by the meta) — workers do not each query the hub repo label.

## 4. Meta loop (a guide — you run it, not a script)

The meta also runs on /loop (dynamic ScheduleWakeup) + /goal (Stop hook). One meta cycle:

1. **Read the board → compute assignments = `meta_sync.sh assign`** (deterministic core): only cards in Ready state (`roadmap.ready_status` —
   the GitHub default board uses `Todo`) + no blocked label + **all `depends_on:` satisfied** (body-line parsing; dependency tokens are
   resolved against the leading code of board card titles — cross-repo agnostic; unresolvable = unsatisfied as the safe default) go to JSON.
   Use `--verbose` to see gate reasons. Rollup is `meta_sync.sh rollup` → appended to the hub repo PROGRESS.
   Before assigning, first converge board consistency with **`meta_sync.sh reconcile`** (issue closed but card≠Done → Done; Done but
   issue OPEN → warning only, auto-close forbidden). Gate-logic regression checks are `meta_sync.sh self-test` (zero network).
   Then the **N-repo strategy consistency check (every meta cycle)**: does the whole board still match the planning gate's `outcome-roadmap`
   platform strategy — look at balance across repos (one repo bloated) and the outcome alignment of cross-dependency clusters. On drift,
   do not create new cards; report it as a gate re-entry signal. If the strategy itself needs re-validation, `strategy-red-team`.
2. **Usage gate**: if the weekly quota is depleted beyond `budgets.weekly_usage_floor_percent`, **stop launching new workers**
   (only finish what is in progress). If the remaining-quota SoT is unclear (open question), be conservative — when unsure, do not launch.
3. **Worker assurance**: launch workers via `worker_spawn.sh` only for repos that have assignments (`max_concurrent_workers` cap + stagger).
4. **Instruction injection**: direct multi-line injection is forbidden — write a task file and `worker_spawn.sh inject <name> <file>`.
   Channel priority 1 = **message broker** (example broker API: HTTP `POST /team/messages` — called by `worker_spawn.sh inject`, durable inbox,
   workers receive via SessionStart auto-inbox/step ① polling; send-keys is a wake-up bonus, so its failure loses nothing).
   When no broker is available, fall back to send-keys (receipt confirmation + retry, appendix B).
5. **Observation**: watch `capture-pane` together with board card movement. If a worker died (`tmux has-session` fails), decide on relaunch.
6. **Rollup**: regenerate `PROGRESS.md` (per-repo + global). dead-man·heartbeat stay as before.
7. **Meta /goal evaluation**: "all repo cards Done + global DoD + cross-repo E2E + production HITL" — if unmet, pace the next
   cycle; if met, report completion.

## 5. Worker contract (only the differences from the single-repo loop)

- config has `board.shared: true` + a shared `roadmap.project_node_id` → **the worker does not create a board** (even attempting creation is forbidden).
- Board reads are its own repo's cards only (auto filter, §3). **Card moves, fields, and evidence go through `board.sh`** (raw graphql forbidden).
- **Check its own inbox at every loop ①**: MCP team_inbox_peek/team_inbox_consume (or HTTP
  `GET /team/inbox/<own-session-name>?consume=true`, example broker API) — the meta's instructions persist here
  (message broker channel). Session name = the repo basename in session-manager mode, otherwise `ul-<basename>`.
- **Outward/destructive acts are meta-gated**: mass issue creation (taskstoissues), merge, and production deploys are never unilateral —
  they go through meta approval via board/approval-queue signals (the safety compensation for unattended bypassPermissions).
- **Spawn authority is the meta's alone.** A worker's Stop hook or session never creates another worker/claude session (the existing no-recursion rule).

## 6. Hard guards — 2 layers = double the runaway-loop risk (mandatory)

The direct grounds are a runaway-session blowup accident plus a multi-session tmux hang incident (validated on a real multi-repo topology).

- Meta and workers **each** run the full §15 guards: `goal.max_iterations` · lock · budgets · dead-man. **Separate lock paths**
  (meta=`ultraloop-meta-$(id -u).lock`, workers=per-repo — the goal-stop-gate.sh default is already per-uid, so a different cwd separates them).
- **Creating claude sessions inside hooks is forbidden** (existing rule). Spawning happens only as a normal tool call by the meta.
- tmux load: if a shared production server must be protected, `orchestration.tmux_socket: ultraloop` (isolated socket `-L`).
  On overload symptoms (slow session responses), degrade to serial launching. For a stale socket: mv it, then relaunch (incident runbook).
- Worker launches are **staggered** (`stagger_seconds`) — launching N at once is forbidden (usage spike + server load).
- effort saving: for scaffold/analysis-type tasks, state the `budgets.effort_by_task` tier in the task file so the worker runs lowered.

## 7. Planning gate (speckit) — N-repo distribution

- The platform spec is **one speckit chain**, and `specs/` lives in **one hub repo** (e.g. the control plane).
- During `speckit-taskstoissues` (gh issue create mapping, SKILL §4.1.3), **create each issue in its owning repo**, put it on the board,
  then `Repository` is automatic (built-in field — derived from the issue's owning repo, cannot be set manually), and assign `Stage`·`Depends-on`
  to distribute. Cross dependencies are made explicit on the board at this point.
- **★ Mass issue creation must go through `issue_populate.sh`** (a double-issuance race is the direct motivation, validated on a real multi-repo topology —
  two cc sessions turned the same plan into issues concurrently, 4 duplicates):
  ```bash
  issue_populate.sh lock <hub-repo>          # GitHub-side lock. exit 4 = another session is writing → abort
  issue_populate.sh ensure <repo> "<title>" [--body-file F] [--label L]   # per card — idempotent
  issue_populate.sh unlock <hub-repo>
  ```
  `ensure` normalizes the title (strips leading `[O1]`/`O1`-style code tokens, lowercases) and compares against existing open issues —
  it even filters notation-variant duplicates. The lock existence check uses a plain list, not the search API (search indexing lag measured).
- The approval marker `roadmap:approved` goes once on a **hub repo** issue (the existing gate as is). Workers launch after approval.

## 8. Implementation status (honestly)

| Area | Status |
|---|---|
| config schema (`repos:`/`board:`/`orchestration:`/budgets extensions) | ✅ implemented (backward compatible: empty repos = existing behavior) |
| Shared board bootstrap (graphql idempotent create+link+Stage) | ✅ `scripts/board_bootstrap.sh` |
| Worker spawn/injection (session manager·tmux + worktree isolation + stagger + receipt confirmation) | ✅ `scripts/worker_spawn.sh` |
| `roadmap_sync.sh` graphql fallback + shared-board repo filter | ✅ implemented |
| Idempotent issuance + multi-session population lock | ✅ `scripts/issue_populate.sh` (added after the race was demonstrated) |
| Meta assignment + cross Depends-on gate + N-repo rollup | ✅ `scripts/meta_sync.sh` (consistency validated on a real multi-repo board) |
| ready_status made configurable (handles the GitHub default board's Todo) | ✅ `roadmap.ready_status` (without it workers saw 0 cards forever — real bug) |
| Unified board-write CLI (card moves·fields·evidence) | ✅ `scripts/board.sh` (validated on a real board: harmless writes + error paths) |
| message broker durable channel (resolves the §12 send-keys open question) | ✅ `worker_spawn.sh inject` channel=auto (round-trip validated) |
| Session-manager session integration (ta-compatible naming + bookmark persistence) | ✅ `orchestration.spawn: session_mgr` (ensure-hot does not start CC — measured correction) |
| Board consistency reconcile + self-test (fixtures) | ✅ `meta_sync.sh reconcile/self-test` (borrows the gh-project-sync pattern, 4/4) |
| GAN quality loop (lane ⑥ optional gate) | ✅ `quality.gan_evaluator` wired (guide) — borrows gan-style-harness, max_rounds hard guard |
| PM strategy stage (before speckit · around issuance · every-loop check) | ✅ 4 pm-skills vendored (phuryn/pm-skills d384f0c) + gstack-autoplan review wiring |
| Meta loop automation | 📖 guide (§4) only — the meta cc performs per this document. Scripting it is future work |
| Cross-repo contract E2E · usage-quota SoT · message broker channel promotion | ❓ open questions (PLAN §12) — not implemented |
