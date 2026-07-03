# CI/CD — layered CI + pre-merge E2E + HITL deploy (ci-cd-hitl)

Core: **CI on every push → green → pre-merge E2E pass → squash merge → CD (staging auto, production=HITL)**.
The approval gate is enforced by the **GitHub server**, not Claude → cannot be bypassed. **Self-hosted runners on every segment (§0)**.

## 0. ★ self-hosted principle — enforced (REQ-CI-0)

Every GitHub Actions job uses **`runs-on: self-hosted` (homelab runner)**. GitHub-hosted (`ubuntu-latest`,
`macos-*`, `windows-*`, etc.) is **forbidden** — per-minute billing, usage caps, and no access to homelab
resources (GPU/docker).
- **Templates**: `assets/workflows/*.yml` are already self-hosted. Only adding labels is allowed
  (e.g. `[self-hosted, linux, x64]`, `config.ci.runs_on`) — reverting to hosted is forbidden.
- **Drift correction**: while bootstrapping or looping, if `ubuntu-latest` etc. appears when creating or
  fixing a workflow, **correct it to self-hosted on the spot** (treated the same as `rules/_base.md` drift correction).
- **Runner presence gate**: before waiting for CI green, confirm the runner is online —
  `gh api repos/<repo>/actions/runners --jq '.runners[]|select(.status=="online")'`.
  No runner = jobs queue forever → **try the runner bootstrap (below) first**; if impossible, do not proceed with the loop + notify (`notify-approval.md`).
- **Runner bootstrap**: register a self-hosted runner per the official guide:
  https://docs.github.com/en/actions/hosting-your-own-runners (verified playbook 2026-06-12, OCMS 3 repos).
  Preflight (gh admin scope · user/org · runtime) → A install the runner (as a service, idempotent) →
  B convert workflows via PR → C identify the three repo-specific pitfalls from logs
  (pnpm↔Node mismatch · CD compose port collision · trigger typo — scripts cannot fix these, the agent diagnoses) →
  D verify green evidence. ⚠️ Two Claude-specific pitfalls: launching the bare daemon gets killed by the
  sandbox (exit 144) → prefer a systemd service or dangerouslyDisableSandbox; secret-guard blocks `.env` in
  command strings → invoke via a script file.
  If sudo is unavailable or it is another host, include a one-line request in the notification:
  "please register a self-hosted runner for `OWNER/REPO` (see the GitHub self-hosted runner docs)".
- **Deploy targets also default to self-hosted infra (homelab)** (`config.deploy`). External cloud deploys are §14 high-risk (approval queue).

## 1. CI — every push, storm control (REQ-CI-1)

`assets/workflows/ci.yml`:
- Every push triggers CI. But **`concurrency: ci-<branch>, cancel-in-progress: true`** (latest per branch only) +
  **layering** (commit=fast lint/type/unit, PR-ready=full test+cov+build+smoke) + **path filters**.
- Cost-storm prevention (tied to `cost_guard.sh`, REQ-CD-3).

## 2. Always watch → pre-merge E2E (REQ-CI-2)

After push, watch with `gh pr checks --watch` (`ship_pr.sh`). Green → **⑥ pre-merge E2E** (`e2e-production.md`) →
must pass before squash merge. Failure → fix on the same branch and retry (bypassing protection is forbidden).

## 3. Board permissions (REQ-CI-3)

Board automation / card transitions = **project-scope PAT/App** (default `GITHUB_TOKEN` cannot). If absent, bootstrap fails +
fallback guidance (`roadmap-model.md` §6).

## 4. CD — staging auto / production HITL (REQ-CD-1)

`assets/workflows/cd.yml`: `main` merge / `v*` → build → auto-deploy to staging → smoke → **production =
Environment approval (HITL)**. Since E2E runs pre-merge, the staging smoke is a **thin re-check**.
- `deploy-production` uses `environment: production` (required reviewers = `config.hitl.reviewers`) so GitHub
  pauses the job and requires human approval. Deploy only after approval → health → GitHub Release.

## 5. HITL confirmation loop (Claude's behavior)

1. Detect waiting: confirm the production job is "waiting" via `gh run list/view`.
2. **Notify** (Discord + auxiliary console): approval-pending URL + staging smoke results + version/PR list to be deployed.
3. **In parallel**: do not force ahead before approval; continue other non-deploy work (same philosophy as the approval queue, `notify-approval.md`).
4. Outcome: approved → deploy → confirm health OK → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/mark_deployed.sh <version>`
   (records the `.ultraloop/prod-deployed` marker = goal completion condition; this is the only creation path) → report.
   Rejected → root-cause issue (`hitl`/`bug`) → fix loop.

## 6. Regression · rollback · circuit breaker

- `nightly-e2e.yml` full regression (REQ-CD-2). Rollback via `workflow_dispatch(rollback_to)`.
- **Cost circuit breaker** (REQ-CD-3): block + notify when CI minutes / concurrent jobs / daily run caps are exceeded (`config.budgets.ci_minutes_per_day`).

## 7. Protection rules (REQ-CD-4)

`main` protected + `required_approving_review_count=0` (unattended auto-merge). If human review is needed, record the
bot-bypass policy **in the PROGRESS view** (traceability tradeoff). Secrets only in Actions/Environment Secrets (no plaintext).
