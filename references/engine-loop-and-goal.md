# Engine — faithful reproduction of /loop + /goal (engine-loop-and-goal) ★

The heart of this skill. It combines the built-in `/loop` (self-pacing) and `/goal` (stop-blocking gate) by **reproducing their behavior exactly**.
`config.engine` controls both.

---

## 1. /loop — self-pacing engine

Behavioral contract of the built-in `/loop`:
- **With an interval** → re-run at a fixed cadence via `CronCreate`; the first tick is immediate.
- **Without an interval (default)** → *dynamic pacing*: run now, and self-pace the next iteration via **`ScheduleWakeup`**.
- **To stop**, **omit** the next `ScheduleWakeup`/`CronCreate` call (the engine ends by "not booking the next one").

Use in ultraloop (in the ⑨ end-of-loop evaluation of every loop):

### 1-a. dynamic (default · recommended — suited to long loops)

`config.engine.loop.pacing: dynamic`.

At the end of every loop, decide the **next wakeup**:
- **Waiting on an external event** (CI watch, E2E container warm-up, approval-queue response, nightly results, etc.)
  → arm a **`Monitor`**. When the event fires (e.g. CI state change, approval result file created), wake and handle it immediately.
  The Monitor filter must catch **both success AND failure** (so a crash/hang does not look like silence).
- **No specific event, just continuing to the next work item**
  → carry straight into the next loop (if the context is alive), or if briefly idle,
  `ScheduleWakeup(delaySeconds=config.engine.loop.idle_wakeup_seconds, prompt="<the same /ultraloop input>")`.
- **Choosing the delay** (mind the cache window): 60–270s when actively polling external state (keeps cache warm),
  1200–1800s when waiting on something that changes on minute scales. Avoid round numbers (300s). Make `reason` specific ("watching CI for #123").

> Put **this run's `/ultraloop` input verbatim** into ScheduleWakeup's `prompt` so the next utterance re-enters the loop.

### 1-b. interval (fixed cadence)

`config.engine.loop.pacing: interval`, `config.engine.loop.interval: "20m"` etc.

```
CronCreate(cron="<interval as 5-field cron>", prompt="<the same /ultraloop input>", recurring=true)
```
The first tick runs immediately (one run right after booking). To stop, `CronDelete`.

---

## 2. /goal — stop-blocking gate (Stop hook)

Reproduces the behavioral contract of the built-in `/goal <condition>` exactly:
- Set a success **condition** (in ultraloop = the DoD or `config.engine.goal.condition`).
- **Stop hook**: every time the agent attempts to stop, the condition is **re-checked**.
  - **Met** → goal clear, stopping is **allowed** ("goal achieved").
  - **Not met** → stopping is **blocked**, `iteration` · `last_reason` **accumulate**, the agent keeps working.
- State (condition · iteration · last_reason) lives in the state file.

### 2-a. Install (plugin-native — no per-repo injection)

The gate ships with the plugin's own hook registration (`hooks/hooks.json`), version-independent via
`${CLAUDE_PLUGIN_ROOT}` — it auto-follows plugin updates. Bootstrap no longer writes it into the target
repo's `.claude/settings.json`; it only removes legacy injected entries (the old injection used a
version-pinned cache path that broke on every update — issue #1). Because the hook is global, the gate
self-guards: outside an ultraloop project (no `ultraloop.config.yaml` up the tree) it allows immediately.
The effective registration is:

```json
{ "hooks": { "Stop": [ { "hooks": [ {
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/assets/hooks/goal-stop-gate.sh"
} ] } ] } }
```

`goal-stop-gate.sh`:
1. **Hard guards first** (§3) — if a cap is exceeded, **allow the stop** (`exit 0`) and record the reason. *Blocking infinite loops is the top priority.*
2. Evaluate DoD satisfaction via `scripts/goal_check.sh`.
3. **Met** → `exit 0` (stop allowed) + record `met` in state.
4. **Not met** → print JSON `{"decision":"block","reason":"<remaining work/last reason>"}` to stdout (stop blocked) +
   `iteration++`, update `last_reason`. The agent receives that reason and continues.

> This is the actual engine of "never stop until 100%". A 1:1 reproduction of `/goal`'s met→clear, not-met→bump-and-continue.

### 2-b. Condition

- `config.engine.goal.condition: "DoD"` (default) → every item of `references/definition-of-done.md` + board fully Done +
  prod HITL approval. `goal_check.sh` evaluates the machine-verifiable portion (board counts · CI · evidence file existence · HITL state).
- A free-form condition string is also allowed (e.g. `"all P0 items Done with E2E evidence"`).

---

## 3. ★ Hard guards (no infinite loops — mandatory, cannot be disabled)

Guard-less Stop/SessionEnd re-entry runs away (past incident: a zero-guard hook exploded into 20k sessions/tokens). Therefore the goal gate
**always** applies the following. If any one trips, the gate **allows stopping** and reports the "incomplete reason".

| Guard | Behavior |
|---|---|
| unconfirmed linked worktree (#4) | In a linked worktree without a human drain confirmation, the gate never blocks a stop — blocking would recruit sibling-worktree sessions as silent extra drainers. Main worktree unchanged. |
| demoted drainer (#3) | This seat once held the drain lease but another drainer now positively holds it fresh → allow stop + notify (a demoted loop must be free to stop) |
| `config.engine.goal.max_iterations` (default 200) | Cumulative Stop blocks exceed the cap → allow stop + escalation |
| `config.engine.goal.lock_file` | Concurrency re-entry lock (stale cleanup after 10 min). If locked, allow stop immediately (prevents duplicate gates) |
| `config.budgets` (loops/tokens/time) | `cost_guard.sh` judges overage → budget-stop (exit 7) → gate allows stop |
| dead-man's-switch | N minutes without progress (`budgets.dead_mans_switch_minutes`) → notify + escalation |

`goal-stop-gate.sh` evaluates **guards before goal_check**. *Stop is blocked only after the guards pass.*

> Extra safety: a subprocess launched by the Stop hook must not make recursive calls like **`claude -p --bare`**
> (never create a new session inside the hook). The gate only *judges*; the actual work is done by the main loop.

---

## 4. The two combined — the lifetime of one loop

```
[loop N]
  ① plan check (cost_guard · heartbeat · approval-queue drain)   ← guard state refresh
  ②~⑧ lane fan-out → merge → board update
  ⑨ end evaluation:
       goal met? ──yes──▶ omit ScheduleWakeup/Cron → main loop ends naturally
              │          (if the agent tries to stop early, the Stop hook re-checks: pass if met)
              └─no──▶ book the next wakeup via /loop pacing (ScheduleWakeup or Cron)
                          (if the agent tries to stop, the Stop hook blocks + iteration++ + reason)
```

- **/loop** owns *when to wake next*; **/goal** owns *whether stopping is allowed*. They are orthogonal.
- In the normal flow, /loop pacing carries the loop forward; the /goal hook acts as the safety net against "premature stops".
- Termination happens only via **goal met (normal)** or **hard guard (safe stop)** — one of the two.

---

## 5. Operations notes

- **Start**: the user runs `/ultraloop [repo]`. Bootstrap → roadmap_sync → loop. With dynamic pacing the first tick is immediate.
- **Interrupt (user)**: `CronDelete` any active cron; for dynamic, omit the next ScheduleWakeup. To disable the goal hook temporarily,
  remove the Stop hook from the target repo's `.claude/settings.json` or set `config.engine.goal.enabled:false` and re-bootstrap.
- **Resume**: the board is the SoT, so wherever the session broke, `roadmap_sync` resumes from that point (§REQ-ST-1).
- **New-run reset**: run counters (run-start · loop-count · heartbeat · goal state) live in the per-repo state directory.
  Full-board-completion (goal met) residue is auto-reset on the next tick. **budget-stop residue is NOT auto-cleared** (the machine
  cannot tell resume from new run) — when starting with a new mission/newly approved board, the loop entry gate calls `cost_guard.sh --reset`.
  If not, the wall-clock cap from the previous run-start applies from the first loop (a conservative false alarm, but a trap).
- **Observation**: `heartbeat.sh` records periodic liveness to Discord/the state file (§observability).
- **Run scope (v0.10)**: `engine.goal.scope` decides what "done" means for THIS run.
  `board` (default) = full-board completion, the original semantics. `milestone:<title>` =
  the run ends when that milestone is drained: `goal_check` counts only that milestone's
  open issues (north-star reference issue excluded), `roadmap_sync` hands the loop only
  that milestone's Ready cards, and the HITL deploy marker becomes
  `.ultraloop/prod-deployed-<milestone-slug>` so a previous milestone's deploy cannot
  satisfy this run. Why: milestones carry per-run goals (north-star.md §2 verdict
  questions) — without machine scope, a one-milestone run either never stops or drifts
  into the next milestone's cards. Scope switches between runs need no state surgery:
  a completed (met) run auto-resets on the next tick; after a budget-stop, start the new
  scoped run with `cost_guard.sh --reset` as usual.

---

## 6. Drain gates — who may drain, from where, at which target (v0.14, issues #2 · #3 · #4)

Three failure modes share one root: **drain state living somewhere worktrees/branches can fork** (a branch-committed
config pointer, per-pwd goal state). The fix is three stacked gates, all enforced deterministically in
`roadmap_sync.sh` (the script that hands out cards) — the agent honors exit codes, it does not re-judge them:

| Gate | Question | Mechanism | Refusal |
|---|---|---|---|
| ① Worktree HITL (#4) | *May this PLACE drain at all?* | `worktree_gate.sh` — linked-worktree detection (`git-dir ≠ git-common-dir`) + per-run confirm token (dies on new run / scope change / `cost_guard.sh --reset`). Forced, independent of `goal.enabled`/`autonomy`. Main worktree: no gate. | exit 4 — prompt the human (context block: scope · board · sibling worktrees · lease holder). Unattended = DENY + approval queue. |
| ② Scope integrity (#2) | *Is the TARGET unforked?* | `ue_active_milestone` — the pointer's SoT is the board (`Active-Milestone:` line in the north-star issue, pm = single writer); config `goal.scope` is legacy fallback/cache. Board unreachable → degraded to config with a warning. | exit 6 — board ≠ config is a broken run target → reconcile via pm; no drain. |
| ③ Single-drainer lease (#3) | *Is this the ONLY drainer?* | `drain_lease.sh` — one seat per repo/board at the hidden ref `refs/ultraloop/drain-lease`. Atomic by construction: create-if-absent and fast-forward-renew are server-side CAS (no check-then-set race). Renews every loop ①; TTL (`engine.goal.lease_ttl_minutes`, default 45) reclaims a dead drainer's seat; transient network keeps a recently-renewed seat (grace ≤ TTL). No remote → local ref CAS in the git common dir (still spans all worktrees of the clone). | exit 6 — another loop holds the seat → demote to read-only/wait, loudly (holder info printed). |

Stop-gate counterparts (fail-open, §3 guard table): an **unconfirmed worktree session is never stop-blocked** — the
old behavior ("not finished — continue /ultraloop loop") recruited sibling worktree sessions as silent extra drainers,
which is exactly how accidental multi-drainer races started; and a **demoted drainer** (lease positively held fresh by
another) is allowed to stop. Goal-met stops release the seat automatically; any other run end should call
`drain_lease.sh release` so the seat frees without waiting out the TTL.
