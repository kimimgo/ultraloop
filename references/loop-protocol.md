# Loop protocol (loop-protocol) — orchestrator + parallel lanes + pre-merge E2E

1 loop = one cycle in which the **orchestrator (sequential controller)** fans parallel lanes out → joins them. It is non-deterministic:
the per-loop workflow is composed dynamically based on issue nature · stack · environment.

## 0. The 9 steps of one loop

```
[orchestrator]
 ① plan check    board→regenerate PROGRESS view (regen_progress.sh) · refresh progress cache (status.sh --refresh) · roadmap gate (roadmap_sync.sh)
                · **board consistency reconcile (meta_sync.sh reconcile — if an issue is closed but its card is not Done, converge idempotently)**
                · **roadmap-strategy consistency check (every loop)**: do the remaining cards still match the planning
                  gate's outcome-roadmap strategic intent — if drift appears (cards multiplying with no strategic
                  relevance, missing pieces for the outcome), do not create new work; **report it as a gate re-entry signal**
                  (§roadmap-model 5.1)
                · environment check (env-check.md) · cost/heartbeat (cost_guard.sh, heartbeat.sh)
                · approval-queue drain (approval_queue.sh drain → unpark resolved items)
 ② lane forming  next N Ready issues (=worktree.max_lanes) — no Depends-on violations + no module collisions
                · stale worktree GC (worktree_mgr.sh gc, in-flight protected) · create per-lane worktrees
[lanes in parallel ③~⑥ — independent (sub)agent per worktree]
 ③ Dynamic TDD   compose the workflow to fit the issue → Red→Green→Refactor + atomic commits (body in the product language)
 ④ push          triggers layered CI
 ⑤ CI green      watch until all bot QA (lint/type/test/build) passes (ship_pr.sh watches)
 ⑥ ★pre-merge E2E real deploy (lane-isolated ports) → agent click/shell scenarios → capture evidence (e2e_*.sh)
                · optional GAN quality loop (config quality.gan_evaluator=true): a gan-evaluator agent scores the E2E
                  evidence against the issue's acceptance-criteria rubric → below threshold = rework · re-evaluate. ★max_rounds
                  hard guard — on overflow, that lane goes Parked + approval queue (no infinite quality loops)
                · optional reliability eval (config eval.enabled=true): critical cards (eval.critical_labels) repeat the core
                  tests/E2E to require pass^k=1.0; others measure pass@k≥threshold (eval-harness skill,
                  else fall back to max_k repeats) → results in .claude/evals/<card>.log. ★max_k hard guard
[orchestrator]
 ⑦ join+merge    squash-merge only lanes that passed E2E (merge-ready) · resolve conflicts serialized
 ⑧ board update  card Done + E2E-Evidence path · bugs/edge cases → new issues · roadmap edits (notify-only+audit)
                — card moves · fields · evidence go through `board.sh status|set|evidence` (unified graphql CLI). No raw-graphql hand-crafting.
 ⑨ end evaluation board fully Done + DoD + prod HITL? — no → pace the next iteration (/loop) · yes → completion report
```
> In N-repo shared-board mode, ① additionally includes a **self inbox check** (MCP team_inbox_peek/team_inbox_consume, or HTTP
> `GET /team/inbox/<session-name>?consume=true`, example broker API) — the meta layer's instructions persist in the message broker (`multi-repo-orchestration.md §5`).

## 1. Principles
- **E2E is pre-merge (⑥)** — only E2E-passing code lands on main. Preserves "main always deployable" (REQ-LOOP-1).
- **✅ only with execution evidence** — "it ran" ≠ "it is correct" (REQ-LOOP-2).
- **The PROGRESS view is regenerated from the board** — direct writes are forbidden (REQ-LOOP-3, removes contention).
- **Only high-risk lanes get Parked + approval queue**; other lanes continue; the loop as a whole never stalls (REQ-LOOP-4).

## 2. Lane (parallel) work unit
Each lane is 1 issue = 1 worktree = 1 (sub)agent. Inside a lane: issue→TDD→push→CI→E2E→merge-ready.
The orchestrator limits parallelism to `worktree.max_lanes` (default 2), and only runs issues **whose module directories do not
overlap** simultaneously (minimizes merge conflicts). Detailed worktree rules: `worktree-strategy.md`.

## 3. Dynamic workflow (Tier 1)
If the issue is "bug fix", write the reproducing test first; "new feature" → acceptance criteria → failing test → implementation;
"refactor" → keep regression tests green — the cycle's workflow is composed to fit the issue's nature. Details in `tdd-layer.md`.

> ⚠️ **Editing `specs/` (spec body · acceptance criteria) during the loop is forbidden — frozen state** (§9.7). If a spec change is
> needed, only via gate re-entry (`roadmap-model.md §5.1`). Step ⑧'s "roadmap edits (notify-only)" means **adding/moving board cards**
> (bugs · edge cases → new issues), not editing the frozen spec body — do not conflate the two.

## 4. join + merge (⑦)
- Only lanes that passed E2E and became merge-ready get squash-merged via `ship_pr.sh`.
- If several lanes are merge-ready at once, **serialize** to resolve conflicts one at a time (rebase/conflict-fix commits).
- Clean up branches · worktrees after merge (`worktree_mgr.sh`).

## 5. Resume (crash-safe)
The board is the SoT, so a broken session loses nothing. On resume, `roadmap_sync.sh` reads the board and continues from the
In-Progress/E2E/Parked cards at that exact point. No PROGRESS.md reconciliation needed (the board is the truth; the view is regenerated).

## 6. Anti-thrashing
Repeating the same blocker is a strike. But an E2E flake is NOT a strike (only deterministic failure after backoff retries — `e2e-production.md`).
3 strikes → `blocked` issue + escalation. High-risk goes to the approval queue before any strike (§notify-approval).

## 7. Pacing the next iteration (⑨ → ①)
If completion is not met, decide the next wakeup via the /loop engine in `engine-loop-and-goal.md` (ScheduleWakeup or Cron).
If met, stop pacing and output the `definition-of-done.md` completion report.
