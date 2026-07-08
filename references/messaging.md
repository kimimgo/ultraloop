# Commit/push/PR messages — the product's working language (messaging)

## 1. Deterministic subject / body in the product language (REQ-MSG-1)
- `type(scope): <subject>` — **type · scope · subject are a deterministic template**. For changelog/semver/board automation to
  parse reliably, the subject must not wobble.
- **Only the body (why/what) is LLM-written, in the product's working language** (non-deterministic). Root causes of spin-offs · fixes · tradeoffs in natural prose.

### Product working language — decided ONCE per project
All artifact prose (board cards, issue/PR bodies and comments, commit bodies, notifications) is written in the
**product's working language**. Precedence for determining it: language of the `config` mission text → language of the
north-star issue → majority language of existing board cards. Decide it **once** per project, record it
(PROGRESS view / project memory), and never re-infer it per message.

## 2. Runtime detection of writing skills
When the product's working language is Korean, `compose_msg.sh` detects whether `~/.claude/skills/humanize-korean` or
`stop-slop` exists. If present, polish the body with that skill; otherwise write inline. **No template stamping**
(body only — the subject keeps the template).

## 3. Examples
- `fix(solver): correct cavity inlet BC`
  Body: "The inlet boundary condition caused pressure divergence → replaced with a fixed-velocity BC. Confirmed residual convergence to 1e-6 through 100 steps."
- `feat(api): add order creation endpoint`
  Body: "Wrapped the cart→order transition in a transaction to prevent partial failure. Verified end-to-end in E2E with the payment-bypass provider."

## 4. Usage
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/compose_msg.sh commit "<scope>" "<what and why>"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/compose_msg.sh pr     "<summary>" "<changes/E2E results>"
```
PR bodies fill `assets/pr_template.md` (includes the E2E evidence section). Notification message bodies use the same tone.

## 5. ★ No tool/automation identity in externally visible text (REQ-MSG-2)
**Every string a collaborator/outsider reads** — board cards · issue comments · PRs · commits — is written in product/project
language only. It must read as work a human did directly.
- **Forbidden tokens**: `ultraloop` · skill names (`pm`/`loop`) · "autonomous/automated loop" · "agent" · "orchestrator" · "lane" ·
  `ue-`/`ul-` prefixes and other tool/internal-mechanism traces.
- **Replacement examples**: "excluded from the eng automated loop" → "kept apart from the development work queue (planning/exploration stage)" ·
  "handled in lane ue-12" → describe only the work itself · "the agent merged it" → "merge completed".
- If already exposed, amend to neutral wording with `gh issue comment <n> --edit-last` (or PR/commit amend).
- If internal operational signals (lane IDs · session names) are needed, keep them **off the board** (local `PROGRESS.md` view · logs only).
- Rationale · recurrence case = `references/failure-modes.md` FM14.
