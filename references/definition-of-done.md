# Definition of Done (definition-of-done) — loop exit condition + integrity

> Done means **every item below** is ✅ with *verifiable evidence* (CI links · E2E captures · board state · numbers), and the **final production
> deploy is HITL-approved and successful**. If even one item is doubtful or unmet, the loop continues (the /goal gate blocks stopping).
> The mission/roadmap **adds** domain-specific items (below is the common baseline). `goal_check.sh` evaluates this.

## Global DoD checklist
- [ ] Every board item **Done** (Backlog/Ready/In-Progress/In-Review/E2E/Blocked/Parked = 0)
- [ ] Every Roadmap-Item passed **pre-merge production E2E** with capture evidence (`E2E-Evidence` field filled)
- [ ] All per-user-type scenarios × E2E PASS (web clicks / CLI shell / real API calls — `e2e-production.md`)
- [ ] Edge-case hunting ≥1 round, every finding resolved or issue-tracked
- [ ] CI green (lint/typecheck/test/build) — bot QA gate passed
- [ ] Test coverage ≥ `config.coverage_target` (default 80%)
- [ ] **Reliability gate** (when `config.eval.enabled`): critical cards pass^k=100%, others pass@k ≥ `eval.capability_threshold` — evidence `.claude/evals/<card>.log` (eval-harness, supplemented by §9.7 deterministic assertions)
- [ ] **Single-command startup** works (README ↔ E2E up contract match, rule packs `references/rules/*` observed)
- [ ] CD proven: `merge → staging auto-deploy → smoke → production HITL approval → deploy`
- [ ] Security/secrets: 0 plaintext secrets, only `.env.e2e`/Secrets, credential lifetime checked (`observability.md`)
- [ ] **Traceability**: every merge via PR, every PR closes an issue, `blocked` 0, `PROGRESS.md` view up to date
- [ ] **Integrity (§9.7)**: any scope reduction / scenario weakening vs. the acceptance-criteria snapshot is recorded and justified in the audit log
- [ ] Final production deploy **HITL-approved and successful** (health OK)

## §9.7 Completion integrity (notify-only kept + non-blocking safeguards)
Because completion judgment includes the agent's own assessment (self-grading), goalpost-moving is made *visible after the fact*:
1. **Acceptance-criteria freeze** — at planning approval, save per-item acceptance criteria and E2E scenarios as an immutable baseline (`roadmap-model.md` §5).
2. **Modification diff notification + audit log** — agent edits to the roadmap/scenarios need no approval (notify-only), but the
   diff vs. the baseline goes to a Discord notification + the audit log. **Scope reduction / scenario weakening must be stated explicitly** (no blocking, full visibility).
3. **Deterministic assertions alongside** — E2E verdicts combine observation with machine checks (HTTP status · DB row counts · file existence · exit codes)
   to reduce pass-by-self-judgment alone.

## Safe-stop (incomplete) report
When a §15 hard guard is hit (loop/token/time caps · approval-queue backlog), the gate allows stopping and **states the reason for incompleteness**:
"loop forever until 100%" is forbidden (REQ-ST-4). If at the end every item is stuck in the approval queue, report "incomplete, waiting on approvals".

## Completion report format (output only when every item is ✅ + production HITL approved)
```
## ✅ ULTRALOOP completion report
- Mission summary / final release tag:
- Board: all items Done (N total, M Epics)
- Per-DoD-item results + evidence links:
- Per-item E2E evidence paths (captures <2MB, merge commit trailer/board field):
- Scenario · E2E results (web/CLI/API + deterministic assertions):
- Edge-case handling:
- CI/CD + production deploy (HITL approver/time/version/health):
- Integrity: modifications vs. acceptance-criteria snapshot (reasons for any scope reduction):
- Cost/time usage (vs. budgets):
- Remaining risks / follow-up recommendations · clean-environment reproduction steps:
```
