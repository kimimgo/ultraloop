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
//   Budget:       maxLanes cap, dropped cards logged (no silent truncation). Merging is NOT here —
//                 the orchestrator serializes ⑦ join+merge outside the workflow.
//
// args: {
//   repo: "owner/name",
//   cards: [{ number, title, goalLink, acceptance, e2e?, module? }],
//   maxLanes?: 2,
//   casting?: { coding?: {model, effort}, verification?: {model?, effort} },
// }

const cards = (args && args.cards) || []
if (!cards.length) return { lanes: [], mergeReady: [], note: 'no cards passed' }

const repo = (args && args.repo) || ''
const maxLanes = (args && args.maxLanes) || 2
const cast = (args && args.casting) || {}
const coding = { model: 'sonnet', effort: 'xhigh', ...(cast.coding || {}) }
const verification = { effort: 'high', ...(cast.verification || {}) } // no model key → inherit main session

const LANE = {
  type: 'object',
  required: ['status', 'summary'],
  properties: {
    status: { enum: ['ready', 'failed', 'parked'] }, // ready = gates green + E2E PASS + PR open
    branch: { type: 'string' },
    pr: { type: 'number' },
    evidencePath: { type: 'string' },
    summary: { type: 'string' },
    blockReason: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object',
  required: ['upheld', 'reasons'],
  properties: { upheld: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } } },
}

const picked = cards.slice(0, maxLanes)
if (picked.length < cards.length)
  log(`lane cap: running ${picked.length}/${cards.length} cards (maxLanes=${maxLanes}) — the rest wait for the next loop`)

const results = await pipeline(
  picked,
  card =>
    agent(
      `You are one coding lane of repo ${repo}, executing board card #${card.number}: "${card.title}".
Goal-link: ${card.goalLink || '(missing — if truly absent on the card, stop and return status=parked)'}
Acceptance criteria:
${card.acceptance}
${card.e2e ? `E2E scenario:\n${card.e2e}` : ''}

Work entirely inside your isolated worktree. Protocol:
1. TDD — write the failing test first (Red), implement (Green), refactor. Atomic commits; commit/PR text in plain product language, never naming any tool, agent, or automation.
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
    return agent(
      `Adversarially verify a completion claim in repo ${repo}. Card #${card.number}: "${card.title}".
Acceptance criteria:
${card.acceptance}
The implementing lane claims: ${lane.summary} (branch ${lane.branch || '?'}, PR #${lane.pr || '?'}, E2E evidence ${lane.evidencePath || '?'}).
Try to REFUTE it: inspect the diff read-only, check each acceptance criterion against actual code/tests, and read the E2E evidence file for a real **PASS** marker (a placeholder or a test passing for the wrong reason is a refutation). Default to upheld=false if uncertain.`,
      { label: `verify:#${card.number}`, phase: 'Verify', effort: verification.effort, ...(verification.model ? { model: verification.model } : {}), schema: VERDICT }
    ).then(v => ({ card: card.number, lane, verdict: v }))
  }
)

const lanes = results.filter(Boolean)
const mergeReady = lanes.filter(r => r.lane.status === 'ready' && r.verdict && r.verdict.upheld).map(r => r.card)
log(`${mergeReady.length}/${lanes.length} lanes merge-ready (verified)`)
return { lanes, mergeReady }
