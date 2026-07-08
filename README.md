<p align="center">
  <img src="assets/hero.png" alt="ultraloop" width="100%">
</p>

<h1 align="center">ultraloop</h1>

<p align="center">
  <em>An autonomous software-engineering loop for Claude Code, built from exactly three mechanisms:<br>
  a <strong>GitHub Projects board</strong> as the single source of truth (WHAT),<br>
  <strong>dynamic multi-agent workflows</strong> designed per work item and codified into reusable scripts (HOW),<br>
  and a <strong>goal engine</strong> that self-paces and refuses to stop before Done (WHEN).</em>
</p>

<p align="center">
  <strong>v0.12.0</strong> &nbsp;·&nbsp; <code>/ultraloop:pm</code> &nbsp;·&nbsp; <code>/ultraloop:loop</code>
</p>

---

## Why

Most "autonomous coding" setups collapse planning and execution into one all-powerful agent. That agent
can silently rewrite its own scope, skip tests, and leave a board that no longer reflects reality.

**ultraloop separates the two jobs and the two permission sets:**

| | `ultraloop:pm` — the planner | `ultraloop:loop` — the engineer |
|---|---|---|
| **Owns** | scope, roadmap, the board | code, branches, merges |
| **Writes** | milestones, issues, acceptance criteria | source, tests, status + progress comments |
| **Cannot** | touch code (no `Write`/`Edit` tool) | define roadmap or change scope |
| **Tools** | `gh`, read-only `git`, search, ask | full toolchain (the loop needs it) |

The board (GitHub Projects v2) is the **single source of truth**. `pm` fills it; `loop` drains it.
Neither can do the other's job — the separation is enforced at the tool-permission layer, not by trust.

## The trinity

```
board (gh Projects v2)  = WHAT to work on   — single source of truth (pm fills, loop drains)
dynamic workflow        = HOW to work on it — designed per card, codified when it recurs
goal (/loop + /goal)    = WHEN to stop      — self-pacing + a stop-gate that re-checks the DoD
```

- **Dynamic workflow ★** — the loop doesn't run one fixed pipeline. For each work item it *designs* an
  orchestration (shape → dependencies → uncertainty → casting → budget), executes it with the Claude Code
  Workflow tool, and **codifies recurring shapes into reusable scripts** (`workflows/*.workflow.js`,
  parameterized by `args`, resumable). Casting is code, not convention: **coding agents run sonnet·xhigh;
  reasoning and verification stages inherit the main session** (run it on your strongest model).
  Methodology: [`references/dynamic-workflow-design.md`](references/dynamic-workflow-design.md).
- **Goal engine** — `/loop` (self-pacing via `ScheduleWakeup`/`CronCreate`, waking on events with `Monitor`)
  plus `/goal` (a Stop-hook gate that refuses to stop until the Definition of Done is met), with hard guards
  against runaway loops. [`references/engine-loop-and-goal.md`](references/engine-loop-and-goal.md).
- **Board = SoT** — every card carries a `Goal-link:` to a milestone goal, which chains to one north star
  (no filler cards). `loop` moves each card through `In Progress → Done` and logs decisions, blockers, and
  evidence as it goes. One board may span N repos (a gh-roadmap multi-repo link); ultraloop stays
  single-repo — each repo runs its own session, executing only its assigned slice (`board.shared: true`).

## Philosophy

1. **The board is the single source of truth.** Scope, priority, and progress live on the
   GitHub Projects board — never in side state. `pm` fills it; `loop` drains it.
2. **Separation of powers, enforced — not trusted.** `pm` owns *what & why* and has **no
   `Write`/`Edit` tool**; `loop` owns *how* and cannot define roadmap or scope.
3. **Workflows are designed, then codified.** Improvise a shape once; the second time it recurs,
   it becomes a script with an `args` contract. The methodology compounds instead of evaporating.
4. **Casting is code.** Model×effort per stage type lives in config and script defaults —
   coding = sonnet·xhigh, reasoning/verification = the main session — not in anyone's memory.
5. **Plain product language.** Board / issue / PR / commit text never names a tool, agent, or
   automation. The history reads as human product work — portable and tool-agnostic.
6. **Outcome over output, red-teamed first.** The roadmap is framed as user/business outcomes,
   and its load-bearing assumptions are attacked (with kill criteria) before any spec is written.
7. **TDD is the unit of progress; merge is earned.** Every change starts from a failing test, and
   `main` only receives code that passed a *real* pre-merge production E2E with captured evidence.
8. **Bounded autonomy.** `/loop` self-paces; `/goal` gates stops. The stop-gate is **always
   fail-open** behind lock / budget / iteration-cap guards, so the loop can never run away.
9. **Isolated parallelism.** Build lanes run in separate git worktrees branched from a fixed
   base, so concurrent cards editing the same files never collide.

## Dynamic workflow — the shipped library

Reusable orchestration scripts, invoked as
`Workflow({scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/<name>.workflow.js", args: {...}})`.
Each is also a reference implementation of the design methodology.

| Script | Shape | Casting |
|---|---|---|
| `milestone-fanout` ★ | **one invocation = one milestone**: a reasoning agent builds the card dependency graph, code validates + schedules parallel waves, lanes execute, a serial integrator merges verified lanes wave by wave until the milestone drains | graph inherits main · lanes **sonnet·xhigh** · verifiers inherit main |
| `lane-fanout` | one card-batch → worktree-isolated TDD lanes → per-lane adversarial verify (no merge) | lanes **sonnet·xhigh** · verifiers inherit main |
| `pm-chain` | strategy perspectives → north star → **red-team barrier** → spec per milestone → prioritized plan | all reasoning — inherits main |
| `adversarial-verify` | claims × diverse lenses → refuters → majority verdict | verification — inherits main |

The fan-out **envelope is the milestone** — the largest scope whose design can be trusted (its contract is
red-teamed and human-approved at the pm gate, and it has a machine drain condition + verdict question).
Epic/board scope is never one invocation; cards are the small-run fallback.

Project-specific shapes the loop codifies land in the target repo's `.claude/workflows/`, named and
committed like any other engineering asset. Design procedure, pattern vocabulary (pipeline / barrier /
judge panel / loop-until-dry / …), casting policy, and the codification rule:
[`references/dynamic-workflow-design.md`](references/dynamic-workflow-design.md).

## Orchestrated skills

ultraloop doesn't reinvent the wheel — it **orchestrates** proven skills. Each phase calls a
specialist skill and falls back to a built-in path if that skill isn't installed.

| Skill | Role |
| --- | --- |
| **gh-roadmap** *(bundled)* | Board structure & setup authority — board, fields, views, Roadmap layout, built-in workflows, multi-repo links. Ships inside this plugin (`skills/gh-roadmap/`); a local copy at `~/.claude/skills/gh-roadmap` takes precedence if present. |
| product-strategy / outcome-roadmap / strategy-red-team / prioritization-frameworks | The PM chain — strategy, outcome framing, assumption red-teaming, prioritization. |
| speckit | Spec authoring. |
| tdd-workflow | Test-driven Red → Green → Refactor. |
| **gstack lane** *(entirely optional)* | If the [gstack](https://github.com/gstackio) skill suite is installed, ultraloop calls it at mapped steps — office-hours/autoplan/spec in planning, investigate/qa-only/review in the loop, health/retro at milestone close, canary post-deploy. Every entry degrades to a built-in path; **merge/deploy authority never leaves ultraloop** (gstack drafts, ultraloop scripts execute). No gstack? Nothing breaks — the probe prints one summary line and moves on. |

Call if present, fall back if absent — loudly, never silently. (full registry with modes,
evidence contracts, and invocation policies: `references/dependencies.md`)

## How the loop works

`pm` plans once and writes the board; `loop` reads the board and ships it, handing back to `pm`
only when scope must change.

```mermaid
flowchart LR
    M[Mission] --> PM
    subgraph PM["ultraloop:pm — plan (one-shot)"]
      direction TB
      P1[strategy] --> P2[outcome roadmap] --> P3[red-team] --> P4[spec] --> P5[prioritize] --> P6[write board]
    end
    PM -->|board approved| B
    subgraph B["ultraloop:loop — execute (self-paced loop)"]
      direction TB
      B1[read board SoT] --> B2[Ready card] --> B3[TDD] --> B4[pre-merge E2E] --> B5[merge + log evidence]
    end
    B -->|scope change / stale board| PM
    B -->|all cards Done + DoD + prod HITL| Z([Shipped])
```

### PM loop — plan → board

```mermaid
flowchart TD
    A[Mission / epic] --> B{Repo + board ready?}
    B -- no --> S[bootstrap_repo.sh<br/>labels · board · CI · goal-gate · worktree.baseRef]
    S --> C
    B -- yes --> C[product-strategy]
    C --> D[outcome-roadmap]
    D --> E[strategy-red-team<br/>attack assumptions + kill criteria]
    E -->|fails gate| D
    E -->|passes| F[spec — speckit chain]
    F --> G[prioritization-frameworks · RICE/ICE]
    G --> H[write milestones · issues · cards<br/>acceptance criteria + E2E scenarios + deps]
    H --> I{User approves scope?}
    I -- no --> D
    I -- yes --> J[label roadmap:approved · freeze spec]
    J --> K[[hand off to loop]]
```

### Build loop — board → shipped

```mermaid
flowchart TD
    A[plan check<br/>regen PROGRESS · dep gate · env · cost/heartbeat · drain approvals] --> B{Ready cards?}
    B -- no --> Z{All Done + DoD + prod HITL?}
    Z -- yes --> DONE([report complete])
    Z -- no --> PACE[pace next iteration via /loop] --> A
    B -- yes --> C[milestone-fanout.workflow.js<br/>reasoning agent builds dep graph → code validates → parallel waves]
    C --> D[per lane: Red → Green → Refactor — sonnet·xhigh<br/>worktree from merged base]
    D --> E[atomic commit → push → tiered CI]
    E --> F{Pre-merge production E2E + adversarial verify}
    F -- fail --> LEFT[leftover → approval queue / next tick]
    F -- pass --> G[serial integrator: squash-merge wave · main stays deployable]
    G --> H[update board: Done + evidence path + comment]
    H --> W{more waves?}
    W -- yes --> C2[next wave from merged base] --> D
    W -- no --> PACE
```

### The /goal stop-gate (safety)

Every stop attempt is re-checked. Guards run **before** the goal check and always allow the stop
(fail-open), so a stuck or runaway loop can never lock the session.

```mermaid
flowchart TD
    S[Stop attempt] --> G1{Lock / budget / iteration cap / dead-man?}
    G1 -- any tripped --> A([allow stop — fail-open, report why unfinished])
    G1 -- all clear --> G2{Definition of Done met?}
    G2 -- yes --> C([clear goal → allow stop])
    G2 -- no --> R[block stop → ++iteration → continue] --> S
```

## Bootstrap

`pm` runs `bootstrap_repo.sh` **idempotently** on first use (and `loop` re-runs it if needed), so
you rarely call it by hand. It probes prerequisites then sets up, skipping anything already done:

- **Labels · board · templates** — sync labels, scaffold the Projects v2 board (falls back to
  Milestones + labels without a project-scope token), copy issue/PR/CI templates.
- **CI/CD · protection** — self-hosted runner check, `main` branch protection, staging (auto) +
  production (HITL) environments.
- **goal stop-gate** — install the fail-open Stop hook into the target repo's `.claude/settings.json`.
- **Dynamic-workflow casting** — record the casting policy (coding model/effort + `max_subagents`)
  into `.claude/settings.json` as the default for fanned-out subagents.
- **Board via gh-roadmap golden template** — views, the Roadmap layout, and built-in workflows
  can't be created through the API, so `copyProjectV2` clones a golden template
  (`config.roadmap.template_node_id`) that already carries three role views
  (Roadmap — PM · schedule / Dev Board / Build Monitor) plus the added Horizon and Target Date fields.
- **★ Worktree optimization** — write `worktree.baseRef` into `.claude/settings.json` from
  `config.worktree.base_ref` (default **`fresh`**). This fixes where parallel build lanes branch:

  | value | lanes branch from | use when |
  |---|---|---|
  | **`fresh`** *(recommended)* | `origin/<default>` | reproducible lanes; unpushed local work never leaks between them |
  | `head` | local `HEAD` | a card must build on top of **unpushed** local commits |

  Lanes use `isolation: "worktree"` — each card gets its own worktree + branch, so concurrent
  edits can't conflict. Unchanged worktrees auto-clean; stale ones are pruned when their PR
  squash-merges (details: [`references/worktree-strategy.md`](references/worktree-strategy.md)).

## Structure

```
ultraloop/
├── .claude-plugin/
│   ├── plugin.json          # registers the skills
│   └── marketplace.json     # this repo as a Claude Code marketplace
├── skills/
│   ├── pm/SKILL.md          # plan deeply (north star → milestone goals) → write the board
│   ├── loop/SKILL.md        # read the board → dynamic workflows → TDD + E2E → ship
│   └── gh-roadmap/          # bundled board authority (Projects v2 structure & setup)
├── workflows/               # ★ reusable dynamic-workflow scripts (lane-fanout · pm-chain · adversarial-verify)
├── references/              # progressive-disclosure docs (dynamic-workflow-design, engine, E2E, DoD, …)
├── scripts/                 # the engine: roadmap sync, board I/O, worktrees, cost guard, goal gate, …
├── assets/                  # hooks (goal gate), CI workflows, templates
└── config.example.yaml      # per-repo config (copy to your target repo root)
```

## Prerequisites

Installing the plugin takes a minute; a *complete* loop needs three pieces of GitHub
infrastructure. Each is checked loudly at bootstrap — nothing fails silently:

| What | Why | Cost |
|---|---|---|
| **Project-scope token** — a PAT (classic) with `project` scope, exported as `UE_PROJECT_TOKEN` | the default `GITHUB_TOKEN` cannot write GitHub Projects v2 boards | 2 min — <https://github.com/settings/tokens> → `project` scope |
| **Self-hosted runner** on the target repo | CI gates assume a runner you control (hosted-runner minutes burn fast in an overnight loop) | ~15 min — <https://docs.github.com/en/actions/hosting-your-own-runners> |
| **Golden template board** *(optional)* | views, the Roadmap layout, and built-in workflows cannot be created via API — a copied template is the only automation | ~20 min once, reused forever; skip it and you get a functional fresh board without the Roadmap views (`skills/gh-roadmap/references/golden-template-setup.md`) |

Discord notifications are optional (console fallback); approvals are a file queue answered from any
shell — zero extra infrastructure.

## Quickstart

```bash
# 1. Add this repo as a marketplace and install the plugin
/plugin marketplace add kimimgo/ultraloop
/plugin install ultraloop@ultraloop

# 2. In your target repo, drop a config at the repo root
#    (or just let /ultraloop:pm seed it — bootstrap copies the example on first run)
cp ~/.claude/plugins/cache/ultraloop/ultraloop/*/config.example.yaml ./ultraloop.config.yaml 2>/dev/null \
  || echo "skip — /ultraloop:pm will seed it"
#    edit `repo:` and the mission, leave the rest on `auto`

# 3. Plan — north star & per-milestone goals first, then milestones, cards (each with a
#    goal-link line), acceptance criteria
/ultraloop:pm

# 4. Loop — reads the approved board and ships it, autonomously
/ultraloop:loop
```

`pm` is a one-shot planning session (re-enter only when the roadmap changes). `loop` self-paces with
`/loop` and gates its own stops with `/goal` until every card is Done *with evidence*.

> **Want to try without installing?** `claude --plugin-dir /path/to/ultraloop`

## Safety

ultraloop is designed to run unattended for hours, so every loop is bounded:

- **Budgets** — `max_loops` and `max_wall_clock_hours` are enforced deterministically; reaching one
  stops the loop and reports *why it is unfinished* rather than churning. A completed run resets
  its counters automatically; starting a fresh run after a budget-stop uses `cost_guard.sh --reset`.
- **Run scope** — `engine.goal.scope: "milestone:<title>"` makes a run end when THAT milestone is
  drained instead of the whole board: the goal gate counts only its issues, the loop is handed only
  its Ready cards, and the deploy marker is per-milestone. Default `"board"` keeps classic semantics.
- **Stall guard** — if the same blocker repeats N times with zero board progress, it escalates for a
  human instead of busy-looping.
- **Bounded fan-out** — workflow concurrency ≤ `workflow.max_subagents`; loop-shaped patterns carry
  dry-out caps in code; nothing inside a workflow spawns sessions.
- **Per-repo state** — loop counters, locks, and goal state are namespaced per repository, so
  concurrent loops never clobber each other.
- **HITL for production** — staging is autonomous; production deploys require a human approval gate.

## Configuration

Everything project-specific lives in one `ultraloop.config.yaml` at your target repo's root. Most
fields can stay empty/`auto` — the loop probes the environment and decides per project. See
[`config.example.yaml`](config.example.yaml) for the full, annotated schema (engine, board, budgets,
E2E, workflow casting).

## License

MIT
