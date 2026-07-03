# Changelog

All notable changes to ultraloop are documented here. Versioning is [SemVer](https://semver.org/).

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
