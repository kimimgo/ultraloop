# Workflow tool — API contract (dynamic-workflow build spec)

> The **methodology** (when/why to fan out, patterns, casting, codification) lives in
> `dynamic-workflow-design.md`. This file is the **contract**: the exact API every `.workflow.js` is built
> to. Read it before authoring or editing a workflow script. "Workflow" = the Claude Code **Workflow tool**
> (deterministic multi-agent orchestration), never GitHub built-in workflows (board side, `gh-roadmap`).

A workflow runs **in the background**: invoking it returns a `runId` immediately and a task notification
arrives on completion. Watch live with `/workflows`.

## 1. Every script starts with `meta`

```js
export const meta = {
  name: 'milestone-fanout',                 // required
  description: 'Drain one milestone per invocation',   // required — shown in the permission dialog
  whenToUse: '...',                          // optional — shown in the workflow list
  phases: [                                  // optional — one entry per phase() call
    { title: 'Graph',   detail: 'reasoning builds the dependency graph' },
    { title: 'Waves',   detail: 'coding lanes per wave' },
    { title: 'Integrate', detail: 'serial merge' },
  ],
}
// body starts here — plain JS, async context (use await directly)
```

`meta` **must be a pure literal** — no variables, function calls, spreads, or template interpolation.
Phase titles in `meta.phases` match `phase()` calls **exactly**. Add `model` to a phase entry when that phase
pins a model.

## 2. Body hooks

| Hook | Signature | Returns / semantics |
|---|---|---|
| `agent` | `agent(prompt, opts?)` | subagent. Without `schema` → final text (string). With `schema` (JSON Schema) → forced StructuredOutput, validated object (model retries on mismatch). `null` if the user skips it or it dies after retries → `.filter(Boolean)`. |
| `pipeline` | `pipeline(items, stage1, stage2, …)` | **default multi-stage.** Each item flows all stages independently — **no barrier**. Stage cb gets `(prevResult, originalItem, index)`. A stage that throws drops that item to `null` and skips its rest. Wall-clock = slowest single-item chain. |
| `parallel` | `parallel(thunks)` | **barrier**: awaits all `() => Promise` thunks. A thunk that throws/errors resolves to `null` (the call never rejects) → `.filter(Boolean)`. Use only when a stage needs ALL prior results at once. |
| `phase` | `phase(title)` | starts a progress group; later `agent()` calls group under it. Inside `pipeline`/`parallel` stages pass `opts.phase` instead (avoids racing global phase state). |
| `log` | `log(message)` | narrator line above the progress tree. **Log any dropped items** (caps/filters/nulls) — silent truncation reads as "covered everything". |
| `workflow` | `workflow(nameOrRef, args?)` | run another workflow inline (saved name or `{scriptPath}`). Shares this run's concurrency cap, agent counter, abort signal, token budget. **One level deep only** — `workflow()` inside a child throws. |

### `agent` options
`{ label?, phase?, schema?, model?, effort?, isolation?, agentType? }`
- `label` — display label override. `phase` — assign to a progress group explicitly (use inside pipeline/parallel stages).
- `schema` — JSON Schema; validation happens at the tool-call layer, so downstream stages consume **data, not prose**.
- `model` / `effort` — per-call casting (see `dynamic-workflow-design.md §2`). **Omit `model` to inherit the main-session model** — that is how reasoning/verification stay on the strongest model. `effort` ∈ `low|medium|high|xhigh|max`.
- `isolation: 'worktree'` — fresh git worktree (EXPENSIVE ~200-500ms + disk). Use ONLY when agents mutate files in parallel and would conflict; auto-removed if unchanged.
- `agentType` — custom subagent type (e.g. `'general-purpose'`, `'code-reviewer'`), composes with `schema`.

### Globals
- `args` — the value passed as the Workflow `args` input, verbatim. Pass arrays/objects as **real JSON**, not a JSON string (a stringified list breaks `args.map`/`args.filter`).
- `budget` — `{ total: number|null, spent(): number, remaining(): number }`. `total` is the turn's token target (null if none). `spent()` = output tokens spent this turn across main loop + all workflows (shared pool). `remaining()` = `max(0, total - spent())` or `Infinity`. The target is a **hard ceiling**: once reached, further `agent()` calls throw. Guard budget loops on `budget.total` (else `remaining()` is `Infinity` → runs to the agent cap).

## 3. pipeline() is the default; barrier is the exception

`pipeline()` unless a stage genuinely needs **all** prior-stage results at once — the only real barrier cases:
dedup/merge across the full set, early-exit on zero count, cross-comparison ("the other findings").
NOT a barrier: "I need to flatten/map/filter first" (do it inside a stage), "the stages are conceptually
separate", "it's cleaner code". A barrier makes fast agents idle until the slowest finishes — real wasted
wall-clock. When in doubt: pipeline.

## 4. Hard limits (the runaway backstops)

- Concurrent `agent()` calls cap at **min(16, cores−2)** per workflow; excess queues.
- Lifetime **≤ 1000 agents** per workflow (loop backstop, far above any real workflow).
- A single `parallel()`/`pipeline()` call accepts **≤ 4096 items** (over → explicit error, not silent truncation).
- No recursion beyond one `workflow()` level; nothing inside a workflow spawns a session.
- `/goal` hard guards (`max_iterations` · budgets · dead-man — `engine-loop-and-goal.md §3`) apply unchanged inside workflow mode.

## 5. Language constraints (plain JS, not TS)

- Type annotations (`: string[]`), interfaces, generics **fail to parse**. Plain JS only.
- Standard built-ins available (JSON, Math, Array…) **except** `Date.now()` / `Math.random()` / argless
  `new Date()` — they throw (they would break resume). Pass timestamps via `args`; stamp results after the
  run; vary randomness by agent index/label.
- No filesystem / Node API. MCP tools reach via ToolSearch (schemas load on demand per agent).

## 6. Iterate & resume

- Every invocation persists its script under the session dir and returns the path. To iterate: **edit that
  file** (Write/Edit) and re-invoke `Workflow({scriptPath})` — do not resend the full script.
- Resume after pause/kill/edit: `Workflow({scriptPath, resumeFromRunId})`. The longest unchanged prefix of
  `agent()` calls returns cached results instantly; the first edited/new call and everything after runs live.
  Same script + same args → 100% cache hit.
- Before diagnosing an empty/odd result, read `<transcriptDir>/journal.jsonl` — it records each agent's actual
  return value. Don't assume cached results are non-empty.

## 7. ultraloop invocation

```
Workflow({ scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/<name>.workflow.js", args: {...} })
```
The shipped scripts (`milestone-fanout`, `lane-fanout`, `pm-chain`, `adversarial-verify`) are the worked
examples of this contract — read them alongside this spec (`dynamic-workflow-design.md §3`). Any board/PR/commit
text produced downstream obeys `messaging.md` (no tool/agent names outward).
