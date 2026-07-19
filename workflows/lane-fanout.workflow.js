export const meta = {
  name: 'lane-fanout',
  description: 'Fan out Ready board cards as worktree-isolated TDD coding lanes, then adversarially verify each lane claim',
  phases: [
    { title: 'Lanes', detail: 'one isolated coding agent per card (casting: coding)' },
    { title: 'Verify', detail: 'adversarial refutation of each merge-ready claim (casting: verification)' },
  ],
}

// Reference implementation of dynamic-workflow-design.md §0–§2.
//   Shape:        card → lane (code) → verify (judge). Verifiable outputs: branch+PR+evidence file, then a verdict.
//   Dependencies: none between cards → pipeline(); a lane's verify starts the moment ITS lane finishes.
//   Uncertainty:  the lane's own "I'm done" claim → exactly one adversarial verifier per lane, nowhere else.
//   Casting:      lane = coding (sonnet·xhigh); verifier = verification (inherit main session, high).
//   Budget:       maxLanes = per-wave parallelism; ALL cards run maxLanes-at-a-time across successive
//                 waves (no silent truncation), stopping only under the token floor. Merging is NOT here —
//                 the orchestrator serializes ⑦ join+merge outside the workflow.
//
// args: {
//   repo: "owner/name",
//   cards: [{ number, title, goalLink, acceptance, e2e?, module? }],
//   maxLanes?: 4,
//   casting?: { coding?: {model, effort}, verification?: {model?, effort} },
// }

const cards = (args && args.cards) || []
if (!cards.length) return { lanes: [], mergeReady: [], note: 'no cards passed' }

const repo = (args && args.repo) || ''
const maxLanes = (args && args.maxLanes) || 4
const cast = (args && args.casting) || {}
const coding = { model: 'sonnet', effort: 'xhigh', ...(cast.coding || {}) }
const verification = { effort: 'high', ...(cast.verification || {}) } // no model key → inherit main session

// ULTRALOOP:METHODOLOGY v1 BEGIN — duplicated VERBATIM in lane-fanout.workflow.js AND
// milestone-fanout.workflow.js (workflow scripts are single-file by contract — no imports,
// workflow-tool-spec.md §5). Byte-parity is enforced by tests/workflow_contract.bats: edit BOTH or the suite fails.
const METHODOLOGY = `MANDATORY METHODOLOGY (required barrier — no fallback, no substitute):
Drive this card with these skills, invoked via the Skill tool by EXACT id. If the Skill tool reports any
of them unavailable, STOP and return status=parked with blockReason "methodology unavailable: <id>".
- superpowers:test-driven-development — governs the build: every behavior begins as a FAILING test,
  committed as a test:* commit BEFORE the feat:/fix:* commit that makes it pass. Commit order on this branch
  is machine-checked before merge (test:* must precede feat:/fix:*); out-of-order work will not merge.
- superpowers:systematic-debugging — the moment any test or gate fails for a reason you do not already understand.
- superpowers:requesting-code-review — after the gates are green, before opening the PR; fold findings in via superpowers:receiving-code-review.
- superpowers:verification-before-completion — before returning status=ready (fresh evidence, never memory).
- superpowers:finishing-a-development-branch — at close-out (do NOT merge; merging stays serialized outside the lane).
Skill ids belong ONLY in these working instructions — never in board, issue, PR, or commit text.
Fill the methodology field of your structured return truthfully; it is cross-examined against the branch.
For a parked or failed return, still include a methodology object (empty skillsInvoked and empty redCommit/greenCommit are fine then).`
const METHODOLOGY_VERIFY = `Also cross-examine the methodology evidence. Run, read-only:
  bash "$CLAUDE_PLUGIN_ROOT/scripts/methodology_check.sh" <branch> --red <redCommit> --green <greenCommit>
and treat any non-zero exit as a refutation. Confirm redCommit and greenCommit exist on the branch, redCommit is
a test:* commit, and redCommit precedes greenCommit. A missing or fabricated methodology object = upheld:false.`
const METHODOLOGY_EVIDENCE = {
  type: 'object',
  required: ['skillsInvoked', 'redCommit', 'greenCommit'],
  properties: {
    skillsInvoked: { type: 'array', items: { type: 'string' } }, // exact superpowers:* ids invoked, in order
    redCommit: { type: 'string' },   // sha of the first failing-test (test:*) commit
    greenCommit: { type: 'string' }, // sha of the feat:/fix:* commit that made it pass
    debuggingUsed: { type: 'boolean' },
    reviewFindings: { type: 'number' },
  },
}
// ULTRALOOP:METHODOLOGY v1 END

const LANE = {
  type: 'object',
  required: ['status', 'summary', 'methodology'],
  properties: {
    status: { enum: ['ready', 'failed', 'parked'] }, // ready = gates green + E2E PASS + PR open
    branch: { type: 'string' },
    pr: { type: 'number' },
    evidencePath: { type: 'string' },
    designDocPath: { type: 'string' }, // repo-relative path of the card's design doc (lands with the merge)
    summary: { type: 'string' },
    blockReason: { type: 'string' },
    methodology: METHODOLOGY_EVIDENCE, // v0.16: test-first evidence, cross-examined against the branch
  },
}
const VERDICT = {
  type: 'object',
  required: ['upheld', 'reasons'],
  properties: { upheld: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } } },
}

// Wave loop: process ALL cards maxLanes-at-a-time across successive waves — no card is silently
// dropped. Each wave runs its batch through the same per-card pipeline(lane → verify). Merging is
// still NOT here; mergeReady is returned for the orchestrator to serialize ⑦ join+merge outside.
const lanes = []
let wave = 0
for (let i = 0; i < cards.length; i += maxLanes) {
  if (budget.total && budget.remaining() < 40000) {
    log(`token floor reached (${Math.round(budget.remaining() / 1000)}k left) — stopping; ${cards.length - i} card(s) not started, they wait for the next loop`)
    break
  }
  const batch = cards.slice(i, i + maxLanes)
  wave++
  log(`wave ${wave}: running ${batch.length} card(s) ${batch.map(c => '#' + c.number).join(', ')}${cards.length > maxLanes ? ` (${Math.max(0, cards.length - i - batch.length)} still queued)` : ''}`)

  const results = await pipeline(
    batch,
    card =>
      agent(
        `You are one coding lane of repo ${repo}, executing board card #${card.number}: "${card.title}".
Goal-link: ${card.goalLink || '(missing — if truly absent on the card, stop and return status=parked)'}
Acceptance criteria:
${card.acceptance}
${card.e2e ? `E2E scenario:\n${card.e2e}` : ''}

${METHODOLOGY}

Work entirely inside your isolated worktree. Protocol:
0. Design → Plan (BEFORE Red, per the design half): first author a concise single self-contained HTML design doc for THIS card's slice — house style (sidebar TOC, semantic Mermaid, one "design intent" note on what was intentionally left out); it describes the SYSTEM being built, never a tool/agent/automation. Save it in your worktree at docs/design/issue-${card.number}.html (it lands with the merge) and return its repo-relative path as designDocPath — do NOT write board fields from inside the worktree; the orchestrator records it on the card at merge time. Then write the card's "## Implementation plan" into the issue body (gh issue edit/comment is fine from here): file structure (files touched, one responsibility each), 3-6 right-sized TDD tasks each with a Consumes/Produces interface block, and NO placeholders (every code step shows code). Steps 1-4 below implement THAT plan.
1. Build per the MANDATORY METHODOLOGY above — superpowers:test-driven-development drives it: the failing test first (Red) committed as a test:* commit BEFORE the feat:/fix:* commit that makes it pass (Green), then refactor. Record the two shas as redCommit/greenCommit in the methodology field. Atomic commits; commit/PR text in plain product language, never naming any tool, agent, or automation.
2. Run the repo's quality gates (format · lint · typecheck · tests + coverage). All must be green.
3. Push the branch and open a PR (do NOT merge — merging is serialized outside this lane).
4. Pre-merge production E2E on a lane-isolated port; write evidence to e2e/reports/ with an explicit **PASS** or **FAIL** final-result marker.
Return status=ready only if gates are green AND E2E evidence says **PASS** AND the PR is open. If blocked, status=parked with blockReason. Never claim what you did not observe in real output.`,
        { label: `lane:#${card.number}`, phase: 'Lanes', model: coding.model, effort: coding.effort, isolation: 'worktree', schema: LANE }
      ),
    (lane, card) => {
      if (!lane) return null
      if (lane.status !== 'ready') {
        log(`lane #${card.number}: ${lane.status}${lane.blockReason ? ' — ' + lane.blockReason : ''}`)
        return { card: card.number, lane, verdict: null }
      }
      const md = lane.methodology || {}
      if (!md.redCommit || !md.greenCommit) {
        log(`lane #${card.number}: ready but methodology evidence missing (red/green commit ids) — rejected`)
        return { card: card.number, lane: { ...lane, status: 'failed', blockReason: 'methodology evidence missing (no red/green commit ids)' }, verdict: { upheld: false, reasons: ['methodology evidence object absent on a ready lane'] } }
      }
      return agent(
        `Adversarially verify a completion claim in repo ${repo}. Card #${card.number}: "${card.title}".
Acceptance criteria:
${card.acceptance}
The implementing lane claims: ${lane.summary} (branch ${lane.branch || '?'}, PR #${lane.pr || '?'}, E2E evidence ${lane.evidencePath || '?'}).
Methodology evidence claimed: red=${md.redCommit || '?'} green=${md.greenCommit || '?'} skills=[${(md.skillsInvoked || []).join(', ') || 'none'}].
Try to REFUTE it: inspect the diff read-only, check each acceptance criterion against actual code/tests, and read the E2E evidence file for a real **PASS** marker (a placeholder or a test passing for the wrong reason is a refutation).
${METHODOLOGY_VERIFY}
Concretely run: bash "$CLAUDE_PLUGIN_ROOT/scripts/methodology_check.sh" ${lane.branch || '?'} --red ${md.redCommit || ''} --green ${md.greenCommit || ''}
Default to upheld=false if uncertain.`,
        { label: `verify:#${card.number}`, phase: 'Verify', effort: verification.effort, ...(verification.model ? { model: verification.model } : {}), schema: VERDICT }
      ).then(v => ({ card: card.number, lane, verdict: v }))
    }
  )
  for (const r of results.filter(Boolean)) lanes.push(r)
}

const mergeReady = lanes.filter(r => r.lane.status === 'ready' && r.verdict && r.verdict.upheld).map(r => r.card)
log(`${mergeReady.length}/${lanes.length} lanes merge-ready (verified) over ${wave} wave(s)`)
return { lanes, mergeReady }
