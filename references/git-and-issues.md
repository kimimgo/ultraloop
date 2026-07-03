# Git · issues · branches · board automation (git-and-issues)

Goal: every development history is traceable as issue ↔ branch ↔ commit ↔ PR ↔ board card ↔ release.

## 1. Branch strategy (trunk-based + short-lived branches)
- `main` — always deployable. **Protected**: no direct push, PR required, required status checks pass,
  no force-push/deletion, `required_approving_review_count=0` (unattended auto-merge allowed — bot bypass, REQ-CD-4).
- Work branches — 1:1 with issues: `feat/<issue#>-<slug>` · `fix/…` · `test/…` · `refactor/…` · `chore/…` · `docs/…`.
- Merge = **squash**. Delete branch · worktree after merge.

## 2. Issues (where all work starts)
- All work starts from an issue: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/new_task.sh <type> "<title>" ["<body>"]`
  → creates labels + board card, checks out a `<type>/<issue#>-<slug>` branch, sets the card Status=In-Progress.
- Labels (`assets/labels.json`): `type:*`, `bug`, `edge-case`, `blocked`, `security`, `perf`, `hitl`, `e2e:fail`, `epic`.
  Status is managed as a **board field**, not a label (the board is the single source of truth).
- Bugs/edge cases/spin-offs become issues the moment they are found (the loop consumes them later). `blocked` is an escalation signal.

## 3. Commits (Conventional Commits) — deterministic subject / body in the product language
Format `type(scope): subject`. **type · scope · subject are a deterministic template** (keeps changelog/semver/board automation stable);
**only the body (why/what) is LLM-written in the product's working language** (non-deterministic). Details in `messaging.md`. Atomicity: one commit = one change.

## 4. PRs (the unit that closes an issue + card)
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/ship_pr.sh ["title"]`
- push → PR (body has `Closes #<issue>` + an **E2E evidence section**, `assets/pr_template.md`).
- Watch CI (`gh pr checks --watch`) → green → **⑥ pre-merge E2E** → on pass `gh pr merge --squash --auto --delete-branch`.
- **Evidence tracking (#20)**: record the E2E evidence path in the merge commit trailer (`E2E-Evidence: <path>`) + the board card's
  `E2E-Evidence` field (traceable even after squash). CI failure → fix on the same branch and retry (bypassing protection is forbidden).

## 5. Board automation (project-scope PAT/App — REQ-CI-3)
- Card creation · field transitions (Status/Evidence) require a **project-scope token** (`config.roadmap.token_env`,
  default env `UE_PROJECT_TOKEN`). The default `GITHUB_TOKEN` cannot do Projects v2 mutations.
- If absent, bootstrap switches to the fallback (Milestone+labels, `roadmap-model.md` §6) and states so in the PROGRESS view.
- Token expiry is checked proactively (`observability.md` credential lifetimes).

## 6. Releases (SemVer)
When deployable value accumulates, tag `main` with SemVer `vX.Y.Z` (feat→minor · fix→patch · breaking→major) → CD builds/
deploys + GitHub Release. Notes are composed from merged PRs/issues (traceability).

## 7. Traceability self-check
Every merge via a PR? Every PR closes an issue? Every Done card has E2E-Evidence? 0 open `blocked`?
PROGRESS view fresh? — checked at every loop ①/⑧ (`progress.sh`).
