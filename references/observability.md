# Observability · cost/time ceilings · credential lifetime (observability)

## 1. heartbeat + dead-man's-switch (REQ-ST-3)
- **heartbeat**: periodic liveness to Discord/state file. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/heartbeat.sh` —
  called at every loop ①. Writes a timestamp to the state file `${TMPDIR:-/tmp}/ultraloop/heartbeat`
  (= `heartbeat.sh`'s `$STATE_DIR/heartbeat`; the dead-man check in `cost_guard.sh` reads the same file).
- **dead-man's-switch**: if more than `config.budgets.dead_mans_switch_minutes` (default 30) has passed since the last
  progress (commit/card move/heartbeat), notify — detects stalls and hangs from the outside.

## Per-loop progress report
Each loop iteration emits a compact progress report so a human can follow along per loop, not only at the end.
At every loop ① (alongside `heartbeat.sh`), write one line — **loop N: cards advanced · stage transitions · blockers · next** —
to the board card (or its linked issue) and, if `config.discord.enabled`, a matching `notify.sh` line. Derive the report from
the state already tracked by `status.sh`/`heartbeat.sh` (loop counter + last-progress timestamp in `${TMPDIR:-/tmp}/ultraloop/`);
do not add a new state dir. A report-write failure never kills the loop (same egress-only, exit-0 contract as `heartbeat.sh`/`notify.sh`).

## 2. Cost/time ceilings (REQ-ST-4) — budget-stop
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/cost_guard.sh` — called at every loop ①. Checks `config.budgets`:
- `max_loops` (0=unlimited, though goal.max_iterations is the ceiling) · `max_wall_clock_hours` (default 24) ·
  `max_tokens` (0=session limit) · `ci_minutes_per_day`.
- On excess, **exit 7 (budget-stop)** → the goal gate permits stopping + a summary notification (prevents the infinite "up to 100%").

> cost_guard, the goal gate, and dead-man are one bundled safety net. When any one of them signals a ceiling, the loop **stops safely**
> and reports it under the "incomplete reasons" of `definition-of-done.md`.

## 3. Credential lifetime (REQ-ST-5)
**Pre-check and renew** git/PAT/bot token expiry. At bootstrap + every loop ①, check `gh auth status`,
the project-scope token (`config.roadmap.token_env`), and the Discord bot token (`config.discord.token_env`) for
validity/imminent expiry. Notify when expiry is imminent — prevents silent auth failures while unattended.

## 4. State unification · resume (REQ-ST-1)
Mutable SoT = the board. PROGRESS.md = a regenerated view. On resume, read the board and continue from that point (no reconciliation rules needed).

## 5. Safety rails (REQ-ST-6)
E2E deploys = local and ephemeral (zero production side effects). Secrets via env/Secrets only. Timeouts and resource caps on long/parallel jobs.
Bypassing protections/HITL is forbidden. Destructive actions go through `notify-approval.md` §7 / the approval queue.

## 6. Runaway-loop prevention memo (important)
The observability scripts (heartbeat/cost_guard) and the goal Stop hook **never recursively create a new claude session**. Hooks and guards
do *verdicts/notifications only*; the actual work is done by the main loop. (Hook re-entry without guards is a runaway — `engine-loop-and-goal.md` §3.)
