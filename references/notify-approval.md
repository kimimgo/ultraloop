# Notifications & approvals — async queue + gateway bot + risk levels (notify-approval)

## 1. Non-blocking notifications (REQ-NTF-1)
Routine events (loop start/end · push · CI · E2E capture · board/roadmap edits · heartbeat) notify Discord and then **proceed**.
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh <level> "<title>" "<message>" [evidence_path]`. A notification failure never
kills the loop (notify.sh always exits 0). Roadmap edits are **notify-only + §9.7 diff/audit log** (REQ-NTF-2).

## 2. Async approval queue (REQ-APR-1) — decision
High risk (§14) means **enqueue into the approval queue + Park that lane**, while **the other lanes/independent work continue**. The loop does not stop.
```bash
approval_queue.sh enqueue <action> <risk> [ttl]   # enqueue + park the lane
approval_queue.sh drain                            # step ①: unpark resolved items
```
The queue is file-based (`${TMPDIR:-/tmp}/ultraloop-approvals/`). exit 0=Y (proceed) · 1=N (alternative/turn into an issue) · 4=hold (no response within TTL).

## 3. Receiving channels — egress-only compatible (REQ-APR-2)
- A **Discord gateway bot (outbound WebSocket)** receives **[Y]/[N] buttons + reason** — no inbound ingress needed
  (compatible with corporate DLP). `scripts/approve_bot.py` (per-approval) or `assets/discord/gateway-bot.example.py` (daemon).
- Secondary: bot polling, **console modal** (`console_modal.sh`, when attended).
- Response: Y → unpark and proceed · N → alternative/turn into an issue.

## 4. hold-TTL escalation (REQ-APR-3)
If a queue item gets no response beyond `config.discord.approval_ttl_minutes` (default 120), **auto-proceed is forbidden**. Instead:
- **Escalate** (raise the level of repeated notifications), and where possible **defer** (push that item back and proceed with other items).
- If at the end every item is stuck in the queue, state **"incomplete pending approval"** in the completion evaluation (`definition-of-done.md`).

## 5. Production deploys (REQ-APR-4)
**GitHub Environment approval (the authority)** + Discord notification (pending URL), doubled. `ci-cd-hitl.md` §5.

## 6. Audit log (REQ-APR-5)
Record every notification/approval (channel · responder · Y/N · reason · time) on the board item/audit log.

## 7. Risk classification (§14)
- **High risk = queue + park** (REQ-RISK-1): production deploys · history rewrite · data/volume deletion (`down -v` (except E2E-isolated
  volumes) · db drop) · large destructive refactors · **major** dependency bumps · secret/permission/billing changes ·
  removal of uncommitted/unmerged worktrees · irreversible external actions.
- **Low risk = notify and proceed** (REQ-RISK-2): normal commits/pushes/PRs/merges · issue and board updates · roadmap change proposals ·
  adding tests · rulepack corrections · local non-destructive E2E startup/teardown · docs.
- **When ambiguous, treat conservatively as high risk** (careful, REQ-RISK-3).
