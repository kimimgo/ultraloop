# Dynamic workflow design (dynamic-workflow-design) ★ the heart of ultraloop

> ⚠️ **Terminology**: "workflow" here means the **Claude Code Workflow tool** (deterministic multi-agent
> orchestration scripts). It is entirely different from GitHub Projects **built-in workflows** (close→Done
> automation) — that is board-side, owned by `gh-roadmap`. Do not mix the two.

ultraloop is three mechanisms and nothing else:

```
board (gh Projects v2)  = WHAT to work on      — the single source of truth (pm fills, loop drains)
dynamic workflow        = HOW to work on it    — this document
goal (/loop + /goal)    = WHEN to stop         — engine-loop-and-goal.md
```

A dynamic workflow is an orchestration **designed at runtime to fit the work item**, then executed with the
Workflow tool. The loop does not run one fixed pipeline; for each unit of work (a card, a planning chain, a
verification pass) it *designs* the workflow — and when a design proves itself, it is **codified into a reusable
script** so the next run calls code instead of re-improvising (§3). Design is a main-session job: the orchestrator
(the strongest reasoning model in the room) designs and judges; subagents execute.

> **Build to the tool contract.** This document is the *method* (when and why to fan out). The Workflow tool's
> exact API — `agent()` / `parallel()` / `pipeline()` / `phase()` / `log()` / `workflow()`, the `meta` block,
> the `args`/`budget` globals, concurrency and agent caps, the pipeline-vs-barrier semantics, the JS-not-TS
> constraints, `schema`, and resume — is the *contract*, specified in `workflow-tool-spec.md`. Read it before
> authoring or editing any `.workflow.js`.

---

## 0. The design loop — five questions, in order

Answer these for the work item at hand. The answers *are* the workflow.

1. **Shape** — what stages does this decompose into? Each stage must have a *verifiable output* (a test that
   fails, a file that exists, a JSON verdict). A stage whose output you can't check is not a stage.
2. **Dependencies** — which stages need each other's output? **pipeline() is the default** (items flow through
   stages independently, no waiting). A **barrier** (`parallel()` then collect) is justified only when a stage
   needs ALL prior results at once: dedup across findings, early-exit on zero count, cross-comparison. "The
   stages are conceptually separate" does not justify a barrier — that's what pipeline models.
3. **Uncertainty** — where can a plausible-but-wrong result slip through (a test that passes for the wrong
   reason, a review that agrees too easily, evidence that looks right)? Put **adversarial verification** exactly
   there, and nowhere else — verification everywhere is verification nowhere (it just burns budget).
4. **Casting** — assign each stage a model × effort from the policy table (§2). The default is written in code,
   not remembered.
5. **Budget & stop** — cap concurrency and total agents; every loop-shaped pattern gets a dry-out or count cap.
   The `/goal` hard guards (max_iterations · budgets · dead-man — engine-loop-and-goal.md §3) apply unchanged
   inside workflow mode: fan-out must never create a runaway.

**Solo check (question zero).** Orchestration has real overhead. A one-file fix, a config tweak, a question with
one answer — do it inline or with a single `agent()`. Fan out only when the shape has genuine width (independent
items) or genuine uncertainty (needs independent verification). Scale with the stakes: a routine card gets a
lane and one verifier; a release-critical card gets a lane and a 3-lens panel.

## 0.5 Fan-out scope — the envelope is the MILESTONE ★

A workflow invocation is expensive, so it should carry the **largest scope whose design can be trusted** — and
that boundary is exactly the milestone. The milestone contract (goal + verdict question + anti-goals +
acceptance) is red-teamed and human-approved at the pm gate; inside it, "the plan is sound" is an earned
assumption. One tier up (Epic / the whole board) that assumption breaks: an Epic is content hierarchy
(`Roadmap-Item`, sub-issue trees), sized inconsistently, with **no drain condition and no verdict question** —
nothing machine-checkable says "this Epic is done".

The milestone is also where every goal-engine hook already points: `engine.goal.scope: "milestone:<title>"`
(the run's stop condition), `engine.autonomy: milestone` (the card-breeding envelope), and the per-milestone
deploy marker. Choosing any other fan-out unit would create a second scope axis that fights the goal engine.

| Unit | Fan-out? | Why |
|---|---|---|
| card / card-batch | ✅ small runs (`lane-fanout`) | the minimum shape; used under `autonomy: card` or for remainders |
| **milestone** | ✅ **the envelope (`milestone-fanout`)** | red-teamed contract + machine drain condition + verdict question — the largest trustworthy scope |
| Epic / board | ❌ never one invocation | no drain semantics; "design is perfect" cannot be assumed across milestones — run milestones in sequence instead |

**Graph → waves (how `milestone-fanout` spends the envelope).** The reasoning model **proposes** the milestone's
dependency graph — hard edges (A merged before B starts) and conflict edges (same modules, never the same
wave) — grounded in the actual repo layout. Deterministic code **validates** it (unknown ids, cycles → one
repair round → serial fallback) and schedules waves: runnable = all hard-deps merged; batch = conflict-free,
≤ `max_lanes`; each wave runs lanes (each lane: design → plan → build) → verify → **one serial integrator** (merge order enforced by structure,
not prompt), then the next wave branches from the freshly merged base. A failed card blocks its dependents —
they return as leftovers for the approval queue, never blind-retried. Model judgment where judgment is needed,
code where correctness is checkable.

## 1. Pattern vocabulary

| Pattern | Shape | Use when | Don't use when |
|---|---|---|---|
| **pipeline** (default) | items × stages, no inter-stage waiting | any multi-stage flow | — |
| **barrier** | all results collected, then next stage | dedup / early-exit / cross-compare | "cleaner code" (it wastes the fast agents' wall-clock) |
| **lane fan-out** | 1 card = 1 worktree-isolated agent | N independent Ready cards | cards touching the same modules (serialize instead) |
| **graph → waves** | reasoning proposes dep graph, code validates + schedules parallel waves | draining a whole milestone in one invocation (§0.5) | scope without a trusted contract (Epic/board) |
| **adversarial verify** | N skeptics per claim, majority | any completion/correctness claim that matters | trivially machine-checkable facts (just check them) |
| **diverse-lens verify** | N verifiers, each a different lens (correctness/security/repro) | a claim can fail in more than one way | one failure mode (identical refuters suffice) |
| **judge panel** | N independent attempts → scored → synthesize winner | wide solution space (design, naming, architecture) | one obviously right answer |
| **loop-until-dry** | keep spawning finders until K rounds find nothing new | unknown-size discovery (bugs, edge cases) | known-size work (just enumerate it) |
| **completeness critic** | one final agent asks "what's missing?" | before claiming a sweep/audit is done | mid-flow (it stalls the pipeline) |

## 2. Casting policy — model × effort per stage type ★

The user-set policy, baked into the shipped scripts as code defaults (config `workflow.casting` overrides):

| Stage type | model | effort | Why |
|---|---|---|---|
| **Coding** — writes/edits source: TDD lanes, fixes, refactors, test authoring | `sonnet` | `xhigh` | best coding-per-token; xhigh closes the gap on hard changes |
| **Reasoning** — designs/judges: workflow design itself, red-team, verdict questions, spec, merge/scope decisions | *(omit — inherit main session)* | `xhigh` | the main session is the strongest model in the room; judgment quality dominates cost |
| **Verification** — adversarial reviewers, E2E evidence auditors | *(omit — inherit)* | `high` | skeptics need reasoning depth, not code speed |
| **Mechanical** — inventories, log parsing, formatting sweeps | `haiku` | `low` | volume work; wrongness is cheap and caught downstream |

Rules that keep the policy honest:
- **Omitting `model` inherits the main-session model** — that is the mechanism behind "reasoning stays on the
  main model". Don't hardcode a reasoning model name; inherit it.
- **The designer and the maker are different agents.** The main session (or a reasoning-cast agent) writes the
  acceptance bar; a coding-cast agent meets it; a verification-cast agent judges it. One agent doing all three
  is how self-graded completion drifts (definition-of-done.md §9.7).
- A skill cannot change the session model itself (the user sets `--model`); casting applies to **subagents**,
  where it *is* enforceable — per-call `model`/`effort` on `agent()`.

## 3. Codification — the library is how the methodology compounds ★

Improvised orchestration evaporates when the session ends. The rule:

1. **First time** a shape is needed → design it ad-hoc with §0, run it inline.
2. **Second time** the same shape recurs → **codify it**: write it as a script with an `args` contract, save it,
   and note the casting/budget that worked. Recurrence, not anticipation, is the trigger — never write a
   speculative workflow.
3. **Every time after** → call the script. Same script + same args = resumable, auditable, tunable in one place.

Where scripts live:
- **Shipped library** — `${CLAUDE_PLUGIN_ROOT}/workflows/*.workflow.js`, the shapes every ultraloop run needs
  (table below). Invoke: `Workflow({scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/<name>.workflow.js", args: {...}})`.
- **Project-local library** — the target repo's `.claude/workflows/`. When the loop codifies a shape that is
  specific to this project (its E2E quirks, its review lenses), it belongs here, named and committed like any
  other engineering asset.

Script contract (all shipped and project-local scripts):
- `export const meta = {...}` pure literal; body is plain JS (no TS syntax, no `Date.now`/`Math.random` — pass
  timestamps through `args`).
- Parameterized entirely through `args`; no hardcoded repo/card values.
- Every agent returns **structured JSON via `schema`** — downstream stages consume data, not prose.
- Results that drop items (caps, filters, nulls from skipped agents) are `log()`ged — silent truncation reads
  as "covered everything" when it didn't.
- Board/PR/commit text produced anywhere downstream obeys messaging.md — no tool/agent names outward.

Shipped library:

| Script | Shape | args (summary) |
|---|---|---|
| `milestone-fanout.workflow.js` ★ | **the envelope (§0.5)**: dep graph (reasoning) → validated waves → lanes → verify → serial integrate, until the milestone drains | `{repo, milestone: {title, goal}, cards: [{number, title, goalLink, acceptance, e2e?, dependsOn?}], maxLanes?, maxWaves?, casting?}` |
| `lane-fanout.workflow.js` | one card-batch → coding lanes (worktree-isolated) → per-lane adversarial verify (no merge) | `{repo, cards: [{number, title, goalLink, acceptance, e2e}], maxLanes?, casting?}` |
| `pm-chain.workflow.js` | strategy perspectives → north-star draft → **red-team barrier** (kill criteria must pass) → spec per milestone → prioritized plan | `{mission, repo, context?, perspectives?}` |
| `adversarial-verify.workflow.js` | claims × lenses → refuters → majority verdict | `{claims: [{id, statement, evidence}], lenses?, votes?, threshold?}` |

The scripts are also the **worked examples** of this methodology — read them as reference implementations of
§0–§2 before writing a new one.

## 4. Post-run: close the loop on the design itself

At milestone close (loop ⑨), spend one beat on the workflow, not just the product: which stage was the
bottleneck, which verification caught something real, which barrier turned out unnecessary. If the answer
changes a script — tune the script (that's the point of having it in code). If a new shape emerged twice —
codify it (§3). This is the mechanism by which the methodology gets better instead of staying a document.

## 5. Safety (unchanged invariants)

- Concurrency ≤ `workflow.max_subagents` (and ≤ `worktree.max_lanes` for lanes); the tool itself caps at
  min(16, cores−2). **Infinite fan-out is forbidden**; loop patterns carry dry-out caps in code.
- No recursion: a workflow may call `workflow()` one level deep; nothing inside a workflow spawns sessions.
- Lane worktrees are cleaned when unchanged; stale ones pruned at PR squash-merge (worktree-strategy.md §4).
- Fan-out cost counts against `config.budgets` like everything else (`cost_guard.sh`).
- Never expose Workflow/agents **in board/issue/PR/commit text** (messaging.md).

## 6. Config mapping

| `config.workflow` key | Meaning |
|---|---|
| `orchestrate: true` | pm/loop core stages run as dynamic workflows (this doc); `false` = solo agent throughout |
| `casting.coding` / `.reasoning` / `.verification` / `.mechanical` | model×effort per stage type (§2). Empty model = inherit the main session |
| `max_subagents` | concurrency cap — actual = min(value, 16, cores−2) |

Bootstrap records the casting defaults into the target repo's `.claude/settings.json` as a hint; the shipped
scripts read `args.casting` first, then these defaults.
