# Crew mode (crew) — single repo · one board · ows worktree lanes as human-attachable peers

> Trigger: `config.crew.enabled: true`. With it false, ignore this document — the existing single-session loop stands as is.
> Grounds: ultraloop always runs inside an ows session, and **ows already implements almost all of crew's plumbing** — worktree lanes,
> a SessionStart lane hook, `TEAM_NAME`→cc-hub inbox, and a report-to-`main` convention. Crew mode does **not reinvent any of it**; it
> *consumes* the ows primitives and adds only the board-side ownership discipline. (ows details: the `ows-ops` skill.)

## 0. Topology — the single-repo, ows-worktree analog of N-repo meta/worker

| Topology | Sessions | Repos | Lanes are | Coordination |
|---|---|---|---|---|
| in-process lanes (existing) | 1 | 1 | invisible subagents (Workflow) | one orchestrator, in-process |
| **crew** (this doc) | **1 main + N lane sessions** | **1** | **ows worktree sessions** `<project>~<slug>` (human-attachable siblings) | shared board + **team_inbox (report to `main`)** |
| N-repo meta/worker (`multi-repo-orchestration.md`) | 1 meta + N workers | N | cross-repo tmux workers | shared board + broker |

- Crew is the **single-repo** shape of meta/worker, but the lanes are **ows worktree sessions** — so a **human can attach to any lane**
  (`ta <project>~<slug>`) or be the `main`, and each lane is a real sibling worktree, not an invisible subagent.
- Each lane runs **the ordinary ultraloop loop**, one card at a time (`worktree.max_lanes: 1` under crew — the parallelism is N lanes, not N×M).
- **`main`** = the coordinator session (where you start crew). It owns the board read, hands cards to lanes, and drains their reports. It is
  not a privileged "meta engine" — it is just the hub the ows lane hook already points reports at.

## 1. ows integration — crew IS the ows worktree lane flow (do not reimplement)

Everything below is provided by ows/cc-hub and fires automatically; crew's job is to *use* it, not to install it.

| Need | ows primitive (already there) | Crew usage |
|---|---|---|
| **Create a lane** (non-TTY, from `main`) | `ows wt-spawn <project> <slug> [--kick "<prompt>"]` | makes `wt/<slug>` branch + `<project>~<slug>` session + cc, started with `TEAM_NAME=<session>` → cc-hub inbox auto-received at SessionStart. `--kick` = the lane's first-turn task (e.g. "run /ultraloop:loop for your assigned card"). |
| **Create a lane** (human, TTY) | `ows wt` picker → `＋ 새 워크트리` | same result; a human joins as a peer. |
| **Lane bootstrap / role** | ows `hooks/worktree-context.sh` (SessionStart) | already injects the lane protocol — *"you = lane `<slug>`; do the inbox briefing; for board execution run `/ultraloop:loop`; commit/PR/record to the board directly; report via `team_inbox_send(to=\"main\")`; `team_inbox_peek` every turn"* — plus **sibling awareness** ("live siblings: …"). Crew relies on this; it does not re-teach the lane. |
| **Coordination channel** | cc-hub `team_inbox_*` (the `team-messaging` skill) | `main` sends each lane its assignment; lanes report claim/done/blocked back to `main`. This is `crew.channel`. |
| **Keep a lane current** | `ows wt-sync <project> [<slug>]` | merges `origin/main` into the lane after other lanes merge; conflict/uncommitted → `merge --abort` + report (safe on a live lane). Run it after ⑦ join/merge so lanes rebuild on a fresh base. |
| **Attribution / naming** | `<project>~<slug>`, worktrees NOT in registry (`git worktree list` = SoT), cwd→project longest-prefix | the ⚡ markers, statusline `❖`, and `ows ls --json` `session` all fold the lane under the parent project automatically. |

> **The ultraloop SessionStart hook coexists with the ows ones** (both fire; multiple SessionStart hooks are additive). ultraloop's prints
> the active line + the board-README context mirror; ows's prints the lane protocol + siblings. Do not duplicate the sibling logic in ultraloop.

### Active delivery — the inbox is not just polled, it wakes (fixes the passive gap)

A durable send alone is passive: an idle lane sees a message only at its next SessionStart / self-wakeup (up to `idle_wakeup_seconds`). Crew closes this at both ends, using only pieces that already exist:

- **Turn-end check (active lane) — the ultraloop Stop hook `hooks/stop-inbox-check.sh`.** At every turn end, if this is an ultraloop team session (`TEAM_NAME` set + an ultraloop config present — so it also serves multi-repo workers, not just crew) and the cc-hub inbox has unconsumed messages, it **blocks the stop and injects them** — so an actively-working lane handles a message at the next turn boundary instead of going quiet. Fail-open (any error → allow stop); it consumes on read, so a drained inbox allows the stop (bounded — it only stays alive while messages keep arriving).
- **Wake-on-send (idle lane) — `scripts/crew_notify.sh <target> "<msg>"`.** The sender writes the durable payload to cc-hub **and** `tmux send-keys` a one-line nudge to the target `<project>~<slug>` so an idle lane reacts NOW. **Wake is standard here, not a bonus** (unlike the N-repo `worker_spawn.sh inject`, where it stays a best-effort extra): the two together give full coverage — active lane = Stop hook, idle lane = wake.
- **Safe because the board is the SoT.** Every message is a POINTER ("look at card #N"); the durable state is on the board. So a missed wake or a consumed-but-unseen message loses nothing — the lane recovers from the board at its next turn. cc-hub failure = slower, never wrong.

## 2. Card ownership — board = SoT, grouped by a product-language workstream (not by "lane")

The ows hook speaks of "`lane:<slug>` cards", but a `lane`/`wt`/session-id **label** on the board is a forbidden tool identity (messaging.md §5 — keep lane/worker/session identifiers off outward board text). The fix is **not** to hide ownership off-board — it is to put it on the board **in product language**, which is exactly what a human team does:

- **The board grouping key is a product-language workstream.** Reuse the Epic / `Roadmap-Item` hierarchy, or a `Workstream`/`Area` single-select field whose **values are feature/area names** (`OAuth login`, `Checkout`). `main` sets it; a lane works its workstream's Ready cards. This is human-legible, so it is ghostwriter-compliant — the one rule is that the field name and its values stay product terms, never `wt`/`lane`/`proj~slug`/a session id.
- **Name the worktree after the workstream** — `ows wt-spawn <project> <workstream-slug>` so the board field value and the lane `<slug>` are the *same product string*; the binding is then visible on the board with zero identity leak. If a slug must be mechanical, keep it off-board and map slug→workstream in team_inbox.
- **`assignee` + `In-Progress` = the lock** (complementary): they mark *"someone is on this card"* so no other lane grabs it — a lock, not a per-lane key, so it holds even when every lane shares one GitHub identity (a single PAT). The **workstream field distinguishes streams; the assignee says "taken"**.
- **Coordinator-assign (default, no race):** `main` sets each Ready card's Workstream + `assignee` + `In-Progress`, then nudges the lane over team_inbox. Single assigner ⇒ no claim race.
- **Self-serve (autonomous lane or a human peer with no active `main`):** the lane claims — `In-Progress` + self-assignee is the lock; a `claim <issue#>` team_inbox message + `crew.claim_jitter_seconds` re-read arbitrates races (**earliest broker timestamp wins**; the loser releases and picks another). A stale claim (peer vanished) expires after `crew.claim_ttl_minutes`. When in doubt, **release** (careful default — same bias as worktree GC).
- Reporting stays **board-first** (card state + Workstream + comments + E2E-Evidence = SSOT); team_inbox is only the low-latency nudge to `main`, never a second source of truth.

## 3. Worktrees, GC, reboot

- Lane worktrees follow the ows convention `<project>/.worktrees/<slug>` (gitignored) — the same isolation as ultraloop lane worktrees, so two lanes never touch the same files.
- ultraloop worktree GC (`worktree-strategy.md §4`) is unchanged and still preserves in-flight/unmerged/non-terminal/queued worktrees — a live lane (its card is non-terminal, its branch unmerged) is never GC'd.
- `~` worktree sessions are **excluded from ows `boot-restore`** by design (experimental side-branches). After a reboot only `main` returns; re-open lanes with `ows wt-spawn` / `ows wt`.

## 4. Human as a peer

- A human attaches to a lane (`ta <project>~<slug>`) or to `main`, and works the ordinary loop. Their manual `In-Progress` + self-assign IS a claim — agent lanes route around it via the same board lock.
- Approvals (`notify-approval.md`) may additionally route to the crew channel so a human already on `main`/a lane can approve inline instead of only via Discord.

## 5. Safety — no recursion, bounded, no meta engine

- **Lanes are spawned only by `main` (a human, or the coordinator session as a normal tool call) — never from a hook, a Stop gate, or inside the loop** (the ows rule + ultraloop N-repo §6 invariant: nothing self-multiplies). `ows wt-spawn` from `main` is a normal call; a lane never spawns another lane.
- Each session runs the full §15 guards independently (max_iterations · budgets · dead-man · stall) with a **per-worktree lock path** (different cwd → different per-uid lock), so a runaway lane cannot block the others or `main`.
- **A lane's /goal defers to `main`** (`engine.goal.lane_defer`, default true). A lane is not responsible for GLOBAL board completion, so its Stop gate must not gate on the whole board — otherwise a lane whose own slice is Done can never satisfy "all cards Done" and **infinite-loops**. `goal_check.sh` detects a worktree cwd and treats the machine DoD as met (the lane stops and is re-woken by the crew wake); `main` (repo root) holds the global goal. Multi-repo workers sit at their repo root (already board-filtered), so they are unaffected.
- Outward/destructive acts (merge to main, production deploy) keep their existing per-session HITL gate; crew does not pool or bypass approvals.
- On overload (slow ows/tmux responses), stop spawning lanes — degrade to fewer, never force. Shared tmux socket load is an ows concern (`ows-ops`): if a lane storm is a risk, stagger `wt-spawn`.

## 6. Implementation status (honestly)

| Area | Status |
|---|---|
| config schema (`crew:` block) | ✅ this release (backward compatible: `enabled:false` = existing single-session behavior) |
| Lane create / sync / bootstrap hook / `TEAM_NAME` inbox / sibling awareness | ✅ **provided by ows** (`ows wt-spawn` · `ows wt-sync` · `worktree-context.sh` · cc-hub) — crew consumes them |
| team_inbox durable channel (report-to-`main`, per-turn peek) | ✅ provided by cc-hub / `team-messaging` — crew consumes it |
| **Active delivery** (turn-end Stop check + wake-on-send) | ✅ this release, e2e-verified — `hooks/stop-inbox-check.sh` (blocks stop + injects on unconsumed inbox; ultraloop-team-session-gated = crew + multi-repo, fail-open) + `scripts/crew_notify.sh` (durable cc-hub send + `send-keys` wake) |
| **Lane /goal deferral** (worktree lane infinite-loop fix) | ✅ this release, e2e-verified — `goal_check.sh` defers a worktree lane's DoD to `main` (`engine.goal.lane_defer`); crew-only bug, single-session + multi-repo unaffected |
| Board ownership = assignee lock + coordinator-assign / self-serve claim | 📖 **guide (§2) only** — `main`/lanes perform it via `board.sh` + `gh`. A `crew_orchestrate` loop for `main` (read board → assign lanes → drain reports → `wt-sync` → repeat) and a `crew_claim.sh` (atomic claim/arbitrate/release + TTL) are the artifacts to add when crew graduates guide → automation (same footing as the N-repo meta loop, multi-repo §8). |
| Lane launch | ✅ `ows wt-spawn` (main) / `ows wt` (human) — no new spawner, safety by design |
| Crew rollup view (who owns what, live) | ❓ open — the PROGRESS view could add a per-assignee column; `ows dash` already shows the lane sub-nodes. Not built yet. |
