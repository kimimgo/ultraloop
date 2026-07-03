# Production E2E (Tier 2) — pre-merge gate + capture + integrity (e2e-production) ★

Tier 1 assertions ≠ E2E. **A Roadmap-Item · PR cannot be Done/merged without passing Tier 2 pre-merge** with capture evidence.
Scripts: `e2e_up.sh` → `e2e_run.sh` → `e2e_down.sh`. The merge gate is `ship_pr.sh` (exit 6 on E2E failure).

## 1. up — real deploy, lane isolation (REQ-E2E-2)

- `docker compose -p ue-<issue#> up` (preferred) or the README **single-command startup** (`runner: readme_command`).
- **Lane isolation**: unique compose project-name (`ue-<issue#>`) + **dynamic port allocation** (starting at `config.e2e.base_port`) +
  volume isolation → prevents parallel collisions. Wait for health (`health_timeout_seconds`) → seed.
- Credentials are injected from `.env.e2e` (`config.e2e.secrets_file`) (§5).

## 2. run — real operation, no mocks (REQ-E2E-3)

Operate it like a human and observe:
- **Web UI** = driven by a browser-automation MCP agent (click/type + **screenshots + DOM readout**, observation-based).
- **CLI/TUI** = command scenarios in a **separate shell session** (transcript + exit codes + outputs).
- **API** = real HTTP + schema/side-effect verification.
- (When needed) **numerics** = real-solver convergence + tolerated error.
Scenario template: `assets/e2e/scenario.template.md`.

## 3. Capture evidence + DLP (REQ-E2E-4)

- Record steps · screenshots · transcripts · health · PASS/FAIL in `e2e/reports/<date>-<item>.md` (`assets/e2e/report.template.md`).
- **Compress/downscale screenshots to < `config.e2e.screenshot_max_mb` per file (default 2MB)**; in reports use **links/thumbnails**
  (embedding originals is forbidden — internal DLP).
- Record the evidence path in the **merge commit trailer + the board `E2E-Evidence` field** (traceable even after squash).

## 4. Secret injection (REQ-E2E-5)

E2E-stack credentials = `.env.e2e` (injected from a local vault/GH Secrets). **Never commit plaintext**; discard at teardown.

## 5. Flake handling (REQ-E2E-6)

Real-deploy E2E is flaky. **Transient failures (ports · timeouts · container warm-up) = backoff retry (≤ `config.e2e.flake_retries`,
default 3)**. Failing even after retries must be reported as a **deterministic failure** + strike. **A flake is NOT a strike** (prevents false escalation).
`e2e_run.sh` classifies transient vs. deterministic failures and retries.

## 6. down — leak prevention (REQ-E2E-7)

On lane teardown, `compose -p ue-<issue#> down -v` (§14 guard: `down -v` volume deletion is high-risk → allowed only for
E2E ephemeral isolation volumes) + **reclaim orphaned containers/volumes/ports**. **Disk watchdog**: `docker system prune`
+ notify when the threshold is exceeded (`e2e_down.sh`).

## 7. Pacing (REQ-E2E-8)

Heavy E2E runs **locally** inside the loop, CI runs a **lightweight smoke**, full regression runs **nightly** (`assets/workflows/nightly-e2e.yml`).

## §9.7 Completion-integrity safeguards (non-blocking)

- **Acceptance-criteria snapshot freeze**: at planning approval, save per-item acceptance criteria · E2E scenarios as an immutable baseline.
- **Modification diff notification + audit log**: agent scenario edits are notify-only, but the diff vs. the baseline is notified/audited.
  **Scope reduction / scenario weakening must be stated explicitly** (no blocking, full visibility).
- **Deterministic assertions alongside**: observation + machine checks together (HTTP status · DB row counts · file existence · exit codes) — reduces pass-by-self-judgment alone.
