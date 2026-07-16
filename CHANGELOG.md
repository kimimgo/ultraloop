# Changelog

All notable changes to ultraloop are documented here. Versioning is [SemVer](https://semver.org/).

## 0.13.0

The **card = container** release. Three orchestrators (pm · design · loop) replace two, skill invocation
becomes explicit and verified (the 1% rule), and each card carries its whole life — plan, design doc,
progress, and evidence — in one place.

### Added
- **Three orchestrator skills.** `ultraloop:pm` (thin planner — north star + seed cards only, insight-first
  fan-out), the new **`ultraloop:design`** (one card → a single self-contained HTML design doc via bundled
  `imgyu-techdoc`, published to an artifact host, plus an on-card implementation plan via `card-planning`),
  and `ultraloop:loop` (the autonomous engine that per card invokes `design`, then TDD-builds through parallel
  waves + pre-merge E2E). `gh-roadmap` becomes a shared board-I/O sub-skill.
- **`references/skill-invocation.md` — the 1% rule.** Orchestrators call mapped sub-skills by exact name; if a
  stage is even 1% relevant, fire it; verify it ran; fail loud, never silent-degrade. Fixes "the referenced
  skills never actually fire" without bloating the plugin.
- **`references/card-container.md`** — one issue holds background + acceptance + Goal-link + `## Implementation
  plan`; a `Design-Doc` card field links the published design doc; E2E evidence is dual-recorded (canonical
  `e2e/reports/*.md` that `goal_check.sh` greps, plus a human mirror on the card).
- **Insight layer, vendored (cherry-picked, with provenance):** `opportunity-solution-tree` (Teresa Torres),
  `identify-assumptions`, `prioritize-assumptions`, `pre-mortem`, `brainstorming` — pm's discovery/risk fan-out,
  so pm delivers a point of view, not just cards.
- **`scripts/config_check.sh` (+ `tests/config_check.bats`)** — a session/run config doctor: token, board access,
  bootstrap marker, runner, sub-skill availability; loud on a missing required item, never a silent proceed.
- **`references/card-planning.md`** — the per-card planning gate (cherry-picked from superpowers `writing-plans`).
- **`references/workflow-tool-spec.md`** — the Workflow-tool API contract that `dynamic-workflow-design.md` builds to.
- **Board fields** `Design-Doc`, `Stage` (Planning/Designing/Building), `Wave`, and four golden-template views
  (Roadmap · Dev Board · Build Monitor by Wave · Card Audit).

### Changed
- **pm is thin** — north star + seed cards only; it no longer pre-decomposes tactics or designs (that is `design` + `loop`).
- **First-slice human gate** replaces whole-board pre-approval — approve once after the first vertical card ships,
  then autonomous to the milestone boundary; per-loop progress reports.
- **Parallelism actually fires** — per-wave lane default 2 → 4; `lane-fanout` no longer hard-drops cards past the
  first batch (a wave loop processes all); `milestone-fanout` warns when a batch collapses to serial.
- **Loop engine hardened** — the `/goal` Stop-hook is forced (non-bypassable, DoD-gated); the loop adopts an
  ultracode posture (workflow-orchestrated by default) and fires background workflows fire-and-continue, polling
  only when a downstream step needs the result.
- `imgyu-techdoc` is **bundled** into the plugin (self-contained; no `~/.claude` dependency).

## 0.12.0

The **lite** release — back to the founding trinity: **board (SoT) × dynamic workflow × goal engine**. Everything
that grew around that core is removed; the weakest leg (dynamic workflow) becomes the strongest. Roughly 2,000
lines of accreted surface are cut and ~400 lines of workflow methodology + reusable code are added.

### Added
- **`references/dynamic-workflow-design.md` ★** — the dynamic-workflow design methodology, promoted from a 3-line
  note to the plugin's centerpiece: the five-question design loop (shape → dependencies → uncertainty → casting →
  budget), a pattern vocabulary (pipeline / barrier / lane fan-out / adversarial · diverse-lens verify / judge
  panel / loop-until-dry / completeness critic), the **casting policy** as a table, the **codification rule**
  (ad-hoc once → script on recurrence → call the script thereafter; project-local shapes go to the target repo's
  `.claude/workflows/`), and a post-run step that tunes the scripts themselves.
- **`workflows/` shipped library** — reusable Workflow-tool scripts, parameterized by `args`, each a reference
  implementation of the methodology: `milestone-fanout.workflow.js` ★ (below), `lane-fanout.workflow.js` (one
  card-batch → worktree-isolated TDD lanes → per-lane adversarial verify, no merge), `pm-chain.workflow.js`
  (strategy perspectives → north star → red-team **barrier** → spec per milestone → prioritized plan; returns
  data — pm still owns board writes), `adversarial-verify.workflow.js` (claims × diverse lenses → majority verdict).
- **Fan-out envelope = the MILESTONE ★** (`dynamic-workflow-design.md` §0.5) — a workflow invocation is expensive,
  so it carries the largest scope whose design can be trusted: the milestone, whose contract (goal · verdict
  question · anti-goals · acceptance) is red-teamed and human-approved at the pm gate and which has a machine
  drain condition. Epic/board is never one invocation (no drain semantics, no verdict question); cards are the
  small-run fallback. `milestone-fanout.workflow.js` implements it as **graph → waves**: a reasoning agent
  (inherits the main session) proposes the card dependency graph (hard edges + same-module conflict edges),
  deterministic code validates it (unknown ids, cycles → one repair round → serial fallback) and schedules
  conflict-free waves ≤ `max_lanes`; each wave runs coding lanes (sonnet·xhigh, worktree) → adversarial verify →
  **one serial integrator** (merge order enforced by structure; board card → Done + evidence), and the next wave
  branches from the merged base. Failed cards block their dependents and return as leftovers for the approval
  queue — never blind-retried. Under `engine.autonomy: milestone` (default) loop-protocol steps ②–⑧ run inside
  this one invocation; the orchestrator keeps ①, ⑨, and the milestone close-out verdict.
- **Casting policy in code** (`config.workflow.casting`) — model×effort per stage TYPE: coding = `sonnet·xhigh`,
  reasoning = inherit the main session (`""`·xhigh), verification = inherit·high, mechanical = `haiku·low`.
  Replaces the flat opus-everywhere `workflow.agents`/`by_phase` scheme; bootstrap records the coding cast into
  the target repo's `.claude/settings.json`.

### Removed (the diet — all resurrectable from git history)
- **`ultraloop:design` skill** and its references (`design-loop-protocol`, `design-tools-map`, `stitch-foundation`,
  `community-refs`), `design_env_check.sh`, and `assets/design/` — UI/UX design is a separate product, not part of
  the loop's essence.
- **Crew mode** (`crew-mode.md`, `crew_notify.sh`, the `stop-inbox-check.sh` Stop hook, `config.crew`,
  `engine.goal.lane_defer`) and **N-repo meta/worker orchestration** (`multi-repo-orchestration.md`,
  `worker_spawn.sh`, `compose_msg.sh`, `board_bootstrap.sh`, `config.repos/orchestration`) — multi-session
  topologies are out; parallelism is the dynamic workflow's job (in-process worktree lanes). "N repos" remains a
  **board** concern: gh-roadmap links N repos to one shared board, and each repo runs its own single-repo
  ultraloop on its assigned slice (`board.shared: true` filters goal gate + Ready picks to this repo — kept).
- **Discord gateway approval bot** (`approve_bot.py`, `assets/discord/`, `discord.mode`) — approvals stay as the
  file queue (`echo Y > <queue>/<id>.result`, one line from any shell) + outbound-only notifications
  (`notify.sh`, console fallback). The HITL production gate is unchanged.
- **GAN quality loop and pass@k reliability eval** (`config.quality`, `config.eval`, the DoD reliability line) —
  verification depth now comes from the adversarial-verify workflow patterns instead of bolt-on gates.
- `references/workflow-orchestration.md` (58 lines of config mapping) — superseded by
  `dynamic-workflow-design.md`; `meta_sync.sh rollup` (N-repo view); `budgets.weekly_usage_floor_percent`,
  `budgets.effort_by_task`.

### Changed
- **pm/loop SKILLs rewired** to the methodology + shipped scripts: loop's lane formation invokes
  `lane-fanout.workflow.js`; pm's planning chain invokes `pm-chain.workflow.js`; both reference maps point at
  `dynamic-workflow-design.md`. gstack lane registry trimmed to pm/loop entries (design rows gone).
- README/plugin/marketplace rewritten around the trinity pitch; two skills + bundled gh-roadmap.

## 0.11.2

Skill-authoring pass over the four bundled skills, following Anthropic's Agent Skills guidance. No engine
behavior changes — every operational gate, safety invariant, config key, and reference path is unchanged;
this reshapes how the skills read, not what they do.

### Fixed
- **Two skill descriptions exceeded the 1024-character Agent Skills limit** — `design` (1270) and
  `gh-roadmap` (1120) are rewritten to 914 and 993 while keeping their trigger keywords and role
  boundaries. Descriptions are the always-loaded metadata, so this also trims per-session context cost.

### Changed
- **Reasoned prose replaces heavy-handed framing** across `design`/`pm`/`loop`/`gh-roadmap` — "IRON RULES",
  `★`, and all-caps `MUST`/`NEVER`/`forbidden`/`mandatory` become instructions that explain *why* they
  matter (an LLM follows a reasoned line better than a bare imperative). The rules' force is preserved
  through the reason; the capability-matrix `❌` and genuine `⚠️` gotchas in gh-roadmap stay as data.
- **`loop` no longer front-loads a reference read** — "read engine-loop-and-goal.md first" becomes "the
  summary in §0 is enough to act; full reproduction in the reference," so a run can start without a second
  file load.

### Added
- **Three-line TL;DR at the top of `design`/`pm`/`loop`** — what the skill does, when it's invoked, and the
  single first action, so a fresh session orients in seconds instead of parsing the whole body.
- **Crew communication cheat-sheet inlined in `loop` §4** — the three proactive report-to-`main` sends
  (start / blocked / done, via `crew_notify.sh --to-main`) and the addressing rule are surfaced where a
  lane actually works; receiving was already automatic (the Stop hook), but proactive reporting had no reminder.

## 0.11.1

### Fixed
- **Crew cc-hub addressing was not project-qualified** — cc-hub `team_messages` routes by a flat `to`/`from` string (the table has
  no project/worktree column), but the crew protocol addressed the coordinator as a bare `main`. With two project crews running at
  once, both mains share the single global `main` inbox → cross-project message theft. Crew now encodes the ows taxonomy in **every**
  name: main = `<project>`, lane = `<project>~<slug>` (ows already sets `TEAM_NAME` to this). New `scripts/crew_notify.sh --to-main`
  derives a lane's own project main (`<project>~<slug>` → `<project>`); `crew.report_to` defaults to it, never a bare `main`. Documented
  as the crew naming taxonomy (crew-mode.md §1). e2e-verified — project-qualified delivery + no leak into a global `main` inbox.

## 0.11.0

Loosens the pm↔loop boundary from card-granular to milestone-granular, puts the project context brief on the board, and adds a
flat-peer crew topology. Backward compatible: an older config missing the new keys keeps the existing behavior (`engine.autonomy`
absent = `card`; `crew.enabled` absent = single-session). The shipped `config.example.yaml` recommends `autonomy: milestone`.

### Added
- **Milestone-envelope autonomy** (`engine.autonomy`) — draws the pm↔loop permission boundary by SCOPE, not by card. `card`
  (the 0.10 behavior) keeps every planning card as pm's; `milestone` (recommended) lets loop **breed its own tactical TDD cards
  inside the active milestone envelope**, admitted only through a 3-gate (Goal-link to the active milestone · no anti-goal conflict
  · no new milestone/Epic — north-star.md §4.5). Strategic scope (new milestone/Epic, anti-goal boundary, north-star edits) still
  escalates to pm. pm's handoff unit becomes the **milestone contract** (goal + verdict + anti-goals + acceptance) + seed cards,
  not an exhaustive card list. Wired into loop-protocol ① (breeding step) and the pm/loop SKILL permission tables.
- **Board README context brief** — the project brief (linked repos · collaborators · special project rules) now lives on the
  board (SoT) via `ProjectV2.readme`. New gh-roadmap `roadmap_readme.sh` (get/set/cache, `--pnode` override); bootstrap seeds a
  fillable `assets/CONTEXT.template.md` mirror and pulls the board README when it exists; the SessionStart hook injects the local
  mirror (cache-only, no graphql) so a fresh session knows the context immediately. Product working language, no tool names.
- **Crew mode** (`crew.*`) — the single-repo shape of N-repo meta/worker, but lanes are **ows worktree sessions** `<project>~<slug>`
  (**human-attachable siblings**): `main` coordinator + N lanes on one board. Built **on ows, not reimplemented** — lanes via
  `ows wt-spawn`, sync via `ows wt-sync`, the lane role + sibling awareness + `TEAM_NAME` inbox from the ows `worktree-context`
  SessionStart hook, coordination via team_inbox (lanes report to `main`). Board ownership = a **product-language workstream** on the
  board (Epic / Workstream field, feature-named — never a `wt`/`lane`/session-id label, messaging §5) with **assignee as the lock**;
  name the worktree after the workstream so slug == field value. Coordinator-assign (single assigner, no race) or self-serve claim
  (In-Progress + assignee lock, earliest-claim-wins). No recursion: only `main`/a human spawns lanes. Reference: references/crew-mode.md.
  The board ownership + a `crew_orchestrate`/`crew_claim.sh` helper ship as a guide (graduate to automation later — same footing as the N-repo meta loop).
- **Active team comms** (crew + multi-repo) — closes the passive-inbox gap so teammates don't just send-and-wait. New Stop hook
  `hooks/stop-inbox-check.sh` (gated to ultraloop **team sessions**: `TEAM_NAME` + an ultraloop config, so it serves both crew lanes
  and multi-repo workers; fail-open): at every turn end, if the cc-hub inbox has unconsumed messages it **blocks the stop and injects
  them**, so an active session handles them at the next turn boundary instead of going idle up to `idle_wakeup_seconds`. New
  `scripts/crew_notify.sh`: durable cc-hub send **+ `tmux send-keys` wake** so an idle session reacts now (wake promoted from
  best-effort to standard). Messages are board pointers (SoT), so a missed wake loses nothing — the session recovers from the board.
  e2e-verified against a live cc-hub (block / allow / gate / durable delivery / session-state sync).

### Fixed
- **Worktree lane infinite loop** (crew / multi-worktree) — a lane runs its own cc session with the same `/goal` Stop gate, which
  evaluated the **whole board**; a lane whose own slice was Done could never satisfy "all cards Done" (and never had the cwd-local
  `prod-deployed` marker), so the gate blocked its stop forever. `goal_check.sh` now detects a worktree cwd and **defers the DoD to
  `main`** (`engine.goal.lane_defer`, default true): the lane stops when its own work is done and is re-woken by the active-comms wake;
  `main` (repo root) still holds the global board goal. Single-session (in-process lanes = subagents, no Stop hook) and multi-repo
  (workers sit at their repo root, already board-filtered) do not match the worktree cwd → unaffected. e2e-verified.

## 0.10.0

Published together with 0.9.0 below as a single release commit.

### Added
- **Milestone run scope** (`engine.goal.scope`) — the machine counterpart of per-milestone
  goals (north-star.md §2). `"board"` (default) keeps full-board-completion semantics;
  `"milestone:<title>"` makes THIS run end when that milestone is drained:
  - `goal_check` counts only that milestone's open issues (north-star reference issue
    still excluded); its blocked-issue check scopes with it.
  - `roadmap_sync` hands the loop only that milestone's Ready cards (all three provider
    paths: milestones fallback, legacy-gh GraphQL, `gh project item-list`).
  - The HITL deploy marker becomes `.ultraloop/prod-deployed-<milestone-slug>`
    (`mark_deployed.sh` writes it, `goal_check` requires it) — a previous milestone's
    deploy can no longer satisfy the next run.
  - No state-key surgery needed between runs: a completed (met) run auto-resets on the
    next tick; after a budget-stop, `cost_guard.sh --reset` starts the new scoped run.
  - New `_lib.sh` helpers: `ue_goal_scope`, `ue_scope_slug`.

## 0.9.0

Two releases folded into one (0.8.0 was never published): the deep-loop upgrade that was
staged as 0.8.0, plus the full English rewrite and the gstack lane.

### Added (English canon + gstack lane)
- **Full English rewrite** of every model-facing text — 3 SKILL.md, 26 reference docs,
  asset templates/configs, ~26 scripts' comments and console strings, and the bundled
  gh-roadmap (14 files). Korean trigger phrases in skill frontmatter are kept (routing).
  Runtime artifact prose (cards/issues/PR/commit text) now follows **the product's working
  language** (precedence: config mission language → north-star issue → existing card
  majority; decided once, recorded, never re-inferred — messaging.md).
- **gstack lane (referenced, never bundled)** — full registry in
  `references/dependencies.md` §4: 15 mapped touchpoints across pm/design/loop with the
  interactive-vs-headless split (interactive skills only where a human is present),
  advisory-only ship/deploy (**ultraloop scripts keep the pen**; `mark_deployed.sh` stays
  the sole HITL deploy-marker writer), evidence adapters (a gstack call that leaves no
  ultraloop-shaped evidence did not happen), an injection guard for QA/browse in the
  unattended loop, and per-entry cost classes. Bootstrap probes the lane: one summary
  line when absent, per-entry report when partial.
- **Onboarding**: README Prerequisites section (project-scope PAT, self-hosted runner,
  optional golden template board), marketplace-aware quickstart, and bootstrap now seeds
  `ultraloop.config.yaml` from the example on first run.
- **Error-message quality rule** — every ✗-class console message states problem +
  probable cause + next action; author-only paths replaced with public guidance.

### Added (staged as 0.8.0, first published here)
- **gh-roadmap bundle** — the authority skill for board structure/setup is now embedded in the
  plugin (`skills/gh-roadmap/`, 14 files). The required dependency is now always satisfied without
  a separate install. Probe priority = local `~/.claude/skills/gh-roadmap`
  (live development copy) → bundle → marketplace cache (`bootstrap_repo.sh`).
- **★ North-star planning protocol** (`references/north-star.md`) — a vertical chain that prevents
  "filler cards":
  - pm chain stage 2 = fix the north star (one measurable final-goal sentence + metrics ≤3 +
    anti-goals ≤3 → frozen as a `north-star`-labeled issue, not a board card).
  - Every milestone requires a **goal sentence + a Yes/No verdict question** (feature drawer ❌ → state transition ⭕).
  - Every card has a **one-line `Goal-link:` gate** — if it cannot be written, the card is not
    created (the idea goes to the parking lot).
  - **Re-alignment every loop**: `regen_progress.sh` regenerates the north star and milestone goals
    at the head of PROGRESS.md from the board (structurally re-injecting the final goal) · start
    comments quote the goal-link line · unaligned Ready cards get blocked+pm escalation ·
    closing a milestone answers the verdict question. Label `north-star` added (labels.json).
- **★ Three new design deep-loop stages** (`design-loop-protocol.md` 9→12 sections):
  - **§2 FLOW** — design the UX flow before any screens: personas and core tasks → sitemap (no page
    without an owning task) → task transition table (element · why it is needed · what appears when
    pressed) → button map (necessity audit) → state matrix
    (loading/empty/error/success) → transition coverage list. Output = FLOW.md (`assets/design/FLOW.md.template`)
    — the SoT for INTEGRATE wiring and the VERIFY task walk. Structurally blocks "shell (hollow) pages".
  - **§7 AUDIT** — deterministic detail gate (`assets/design/audit.js`): machine-checks every page for
    typographic clipping (button text short on pixels), font drift (families outside the allowed set /
    exceeding the type scale), dead-button candidates, shell (hollow) signals (placeholder · empty canvas),
    horizontal overflow, and WCAG low contrast — **0 violations** required to enter RE-SCORE.
  - **§9 WALKTHROUGH** — a usage simulation that gives a cold model only the tasks from FLOW and has it
    *perform* them as the persona (getting stuck · "why does this button exist?" = ranked gaps).
    Handoff artifacts = DESIGN.md **+ FLOW.md** (pm quotes it as the seed for E2E scenarios).
- **★ Rulepack 4-gate** (`tdd-layer.md` §3.5) — every lane enforces format·lint·type·test+coverage
  before merge using per-language/stack standard commands (py/ts/go/rust matrix). Coverage is judged
  **per card** (no hiding in the overall average). 3 consecutive failures of the same gate = Parked + approval queue.

### Fixed (found in the v0.7.0 evaluation)
- **No run-state reset** — new `cost_guard.sh --reset` (cleans run-start · loop-count · heartbeat · goal state).
  Full-board-completion (goal met) leftovers are auto-reset on the next tick; for budget-stop leftovers
  the loop entry gate runs --reset on a new run
  (otherwise the first loop false-triggers the wall-clock ceiling against the previous run-start).
- **Recursive-spawn guard was comment-only** — inject an `ULTRALOOP_WORKER=1` marker into worker
  sessions + `worker_spawn.sh` now blocks spawn/inject from a worker in code (list/capture are reads, so allowed).
- **README overstated the token budget** — state explicitly that `max_tokens` is delegated to the
  harness (reserved), distinct from the enforced items (max_loops · wall-clock).
- **Default config template_node_id was a personal board id** — replaced with an empty default + example comment.
- The goal_check milestones fallback counted the north-star reference issue as unfinished work — now excluded.

### Upgrading from ≤0.7
- Console/log output and regenerated local views (PROGRESS.md headers) switch to English;
  board/issue/PR prose follows your product language as before — existing Korean boards
  stay Korean.
- If your board was created with the old bundled gh-roadmap example (`In Progress`,
  space), rename the Status option to `In-Progress` (hyphen) in the board UI — core
  scripts match the hyphenated form.
- Fresh runs after an old budget-stop still need `bash scripts/cost_guard.sh --reset`.
- Horizon field example options are now `Long-term/Mid-term/Short-term` (previously Korean labels);
  existing boards keep working — field creation is idempotent and skips existing fields.

## 0.7.0

### Added
- **Loop progress statusline + SessionStart exposure** — loop progress as a one-line bar.
  - `scripts/status.sh` — `--refresh` (board Done ratio + loop count/elapsed → `status.json` cache; in loop ①),
    `--line` (cache → `[▓▓▓▓░░] 62% · 8/13 · 2▶ · 1⛔ · loop7 4h12m`).
  - `hooks/hooks.json` + `hooks/session-start.sh` — in an ultraloop project, show one **"active + progress" line
    at first session start** (cache only, no graphql — no latency). Silent in non-projects.
  - Wired `status.sh --refresh` into loop ① (`loop-protocol.md` · loop SKILL §4).
  - Statusline display: reads `status.json` (per-repo `/tmp` cache) directly and adds one line (integrated on the user statusline side).

## 0.6.1

### Fixed (3-model audit — Codex gpt-5.5 + Claude Opus; no impact on default behavior — gate hardening and consistency)
- **Unified Status option names** — `In Progress` (with a space) / `Todo` in `meta_sync.sh` and the loop/pm SKILLs → canonical
  (`project-fields.json`: `In-Progress`/`Ready`). Fixes card-move failures (exit 5) and warnings never firing.
- **cost_guard counter pollution** — the goal Stop gate was incrementing loop-count on every stop attempt; split out (`--no-tick`).
- **Hardened E2E verdict** — `grep -i PASS` (false positives on `password`/`bypass`) → `**PASS**`/`**FAIL**` final-result markers.
  `goal_check`, which only counted reports, now verifies unresolved FAIL/PASS marker content.
- **Approval security** — `approve_bot` empty approver list = anyone can approve → fail-closed; `bash -c`
  command injection in `approval_queue` → direct argument-array execution; `approve_bot` default config path = target repo cwd.
- **Disk watchdog** — global `docker system prune` in `e2e_down` (deleted other projects' caches on a shared host) →
  dangling images/build cache only.
- **E2E isolation** — `e2e_up` did not export `UE_LANE` (lanes shared DB volumes) and did not inject `.env.e2e` → export + `--env-file`;
  compose-mode health timeouts now count as failures (no silent success).
- **Board pagination** — fixed GraphQL `first:100` in `roadmap_sync`/`meta_sync`/`board` →
  `--paginate` cursor (prevents dropping cards beyond 100).
- **Bootstrap marker** — was written even with gh-roadmap missing or 0 runners → only when prerequisites are met (prevents locking in an incomplete state).
- **HITL reviewer registration** — actually registers the reviewer payload on the production Environment (previously only the environment was created).
- **prod-deployed marker** — `.ultraloop/prod-deployed` was required by the goal exit condition but nothing created it →
  new `scripts/mark_deployed.sh` + ci-cd-hitl wiring.
- **worktree GC** — `git diff` (cannot see untracked files) → `git status --porcelain` (accurately preserves uncommitted work).
- **design `integrate.py`** — hardcoded foamlab/m11 absolute paths and tokens → a generic config/CLI-driven integrator.
- **README** — stale 2-skill/v0.4.0 content → aligned to design→pm→loop / v0.6.0.
- Honest comments for budgets `max_tokens`/`ci_minutes_per_day`: marked best-effort (not implemented).

## 0.6.0

### Added
- **Reliability eval gate (pass@k / pass^k)** — wires the `eval-harness` skill as a dependency. With `config.eval.enabled=true`,
  card verification gains a reliability dimension: critical cards (`eval.critical_labels`) run the core tests/E2E
  repeatedly and require pass^k=1.0 (all passing), while other cards measure pass@k ≥ `eval.capability_threshold`.
  Falls back to `eval.max_k` repeated runs when the skill is absent. Evidence goes to `.claude/evals/<card>.log`.
- Wiring: `config.example.yaml` (`eval:` block), `references/dependencies.md` (§2 map · §3 rules),
  `references/loop-protocol.md` (E2E stage ⑥), `references/definition-of-done.md` (DoD checklist).
- Default `eval.enabled=false` — when off, existing loop behavior is unchanged (backward compatible).

## 0.5.0

### Added
- **New skill `ultraloop:design`** — the design half of the loop, run BEFORE pm. Orchestrates Google Stitch
  (foundation) + the harness's verified design tools (taste-design, artifact-design, impeccable, taste-skill,
  frontend-design, stitch-{design,build,utilities}, gstack-design-*, tri-model-review, gemini-image-eval,
  playwright-cli, artifacts traefik publish) into ONE verified loop:
  scope → cold multi-model critique (codex+gemini, no leading, N angles incl. domain lens) → design-system
  foundation → Stitch generate → integrate (token-normalize + cross-nav + real data canvases) →
  render-verify → re-score → iterate to a numeric target → hand an approved DESIGN.md to pm.
- References: `design-loop-protocol.md`, `design-tools-map.md`, `stitch-foundation.md`, `community-refs.md`.
- Assets: `assets/design/{DESIGN.md,SITE.md,next-prompt.md}.template`, `integrate.py`, `charts.js`.
- Script: `scripts/design_env_check.sh` (idempotent tool-availability check).
- Skill order is now **design → pm → loop**; plugin/marketplace manifests + keywords updated.
- Empirically validated on foamlab (2026-06-23): a 5/100 "color-copied" mockup rebuilt to codex 84 /
  gemini 92 via this loop. Stitch prompting rules + MCP connection captured from official docs + live runs.

## 0.4.1

### Fixed
- `references/messaging.md`: forbidden-token list still named the old skill name (`build` → `loop`).
- `assets/project-fields.json`: added `Start Date` (DATE) for parity with `gh-roadmap` `fields.json`
  (the Roadmap view needs a Start+Target pair to draw duration bars on the fallback path).

## 0.4.0

### Changed
- **Renamed skill `build` → `loop`** (`ultraloop:build` → `ultraloop:loop`).
- **ultraloop now ORCHESTRATES proven skills** rather than reimplementing them.
  `gh-roadmap` is declared a **REQUIRED dependency** (the authority for board
  structure/setup). See new `references/dependencies.md`.

### Added
- **Workflow orchestration enforced.** Phases now run through the Claude Code
  Workflow tool (`opus` / `ultracode` / `dynamic`) via new `config.workflow`
  (per-agent model/effort/max_subagents plus `by_phase`). See new
  `references/workflow-orchestration.md`.
- **Bootstrap auto-enforced on skill entry** via a `.claude/.ultraloop-bootstrapped`
  marker.
- **Golden-template provisioning of board views.** Board views, the Roadmap
  layout, and built-in workflows are now provisioned by cloning a `gh-roadmap`
  golden template (`copyProjectV2`); `config.roadmap.template_node_id` selects it.
  Project fields gain **Horizon** and **Target Date**, and the auto-add workflow
  is copied from `gh-roadmap`.

## 0.3.0

### Added
- **README: philosophy + per-loop flowcharts.** New *Philosophy* section (8 principles) and a
  *How the loop works* section with mermaid flowcharts for the overall loop, the PM loop, the
  Build loop, and the `/goal` stop-gate.
- **README: Bootstrap section** documenting what `bootstrap_repo.sh` sets up, including the new
  worktree optimization.
- **Worktree optimization in bootstrap.** `bootstrap_repo.sh` now writes `worktree.baseRef`
  (from `config.worktree.base_ref`, default `fresh`) into the target repo's
  `.claude/settings.json`, fixing where parallel build lanes branch (`fresh` = `origin/<default>`,
  reproducible; `head` = local unpushed HEAD).
- `config.worktree.base_ref` knob in `config.example.yaml`.
- `references/worktree-strategy.md` §0 documenting `baseRef` semantics and the recommended `fresh`.

## 0.2.0
- pm/build two-skill plugin: `ultraloop:pm` (plan → write the board) and `ultraloop:build`
  (read the board → TDD + pre-merge E2E → ship), with the GitHub Projects board as the single
  source of truth.
