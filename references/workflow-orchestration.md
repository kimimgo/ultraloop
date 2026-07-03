# Workflow orchestration — opus · ultracode · dynamic ★

> ⚠️ **Terminology**: "workflow" here means the **Claude Code Workflow tool** (multi-agent orchestration).
> It is entirely different from GitHub Projects **built-in workflows** (close→Done automation) — that is board-side and
> handled by `gh-roadmap` / `roadmap-model.md`. Do not mix the two.

`config.workflow` controls this: whether pm·loop's core stages are processed sequentially by a single agent, or **fanned out
to multiple agents via the Workflow tool**.

---

## 1. The reality of forcing (honest)

A skill (markdown) **cannot change the session model directly** — the model is set by the user via `--model`. So "forcing opus"
is implemented as follows (not a hard model force):

1. When calling Workflow/Agent, specify the **subagent's** `model`/`effort`/`agentType`/`isolation` (this is possible).
2. The SKILL **strongly instructs** that core stages be orchestrated via Workflow.
3. Bootstrap records `config.workflow` in the target repo's `.claude/settings.json` (a *recommendation* hint for the session default model).

> Hard blocking (rejecting non-Workflow work with a PreToolUse hook) is **not used** — it obstructs normal work and is fragile.

---

## 2. Settings → Workflow/agent() mapping

| `config.workflow` | Application |
|---|---|
| `orchestrate: true` | orchestrate core stages with the Workflow tool (patterns below) |
| `mode: ultracode` | fan stages out to multiple agents via `parallel()`/`pipeline()` |
| `mode: solo` | a single `agent()` (small-scale work) |
| `pacing: dynamic` | dynamic pacing — consistent with `engine.loop.pacing` |
| `agents.model` | `agent(prompt, {model})` |
| `agents.effort` | `agent(prompt, {effort})` |
| `agents.max_subagents` | concurrency cap — actual concurrency = `min(value, cores-2)` |
| `by_phase.pm` / `by_phase.loop` | per-phase overrides (absent → inherit the `agents` defaults) |

---

## 3. Per-stage patterns

- **pm planning chain** — fan out strategy·roadmap·red team·spec·prioritization.
  - Dependent stages use `pipeline()` (the previous stage's output is the next input); independent multi-perspective ones use `parallel()`.
  - `strategy-red-team` is a **barrier**: entering the spec stage before it passes is forbidden (`dependencies.md`).
  - Apply `by_phase.pm`'s model/effort/max_subagents.
- **loop lanes** — fan out N Ready cards as lanes.
  - Each lane = `agent(..., {isolation: "worktree"})` — prevents file conflicts (`worktree-strategy.md`).
  - model/effort = `by_phase.loop`, concurrent lane count ≤ `max_subagents` and ≤ `worktree.max_lanes`.
- **Verification** — run E2E/reviews as adversarial multi-perspective (multiple verifiers score independently, majority decides).

---

## 4. Safety

- `agents.max_subagents` and `budgets` (tokens/time/loops) cap concurrency and cost. **Infinite fan-out is forbidden.**
- Lane worktrees are cleaned automatically when unchanged; stale ones are pruned at PR squash-merge.
- Never expose the use of Workflow/agents itself **in board/issue/PR/commit text** (`messaging.md`).
- The `/goal` hard guards (`engine-loop-and-goal.md` §3) apply unchanged in Workflow mode — fan-out cannot create a runaway.
