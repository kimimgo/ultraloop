export const meta = {
  name: 'adversarial-verify',
  description: 'Refute claims with diverse-lens skeptics; majority verdict per claim',
  phases: [{ title: 'Verify', detail: 'independent refuters per claim × lens' }],
}

// Reference implementation of dynamic-workflow-design.md §1 (adversarial / diverse-lens verify).
// Generic: use it on completion claims, review findings, E2E evidence, migration results — anything where
// a plausible-but-wrong "looks done" can slip through. Not for machine-checkable facts (just check those).
//
//   Shape:        claim → N lens-refuters → majority verdict. Verifiable output: per-claim boolean + reasons.
//   Dependencies: claims are independent → pipeline(); lenses within a claim are independent → parallel()
//                 (a true barrier per claim: the verdict needs all votes).
//   Casting:      verification — model omitted (inherit main session), effort high.
//   Budget:       agents = claims × lenses, both caller-bounded; no loops.
//
// args: {
//   claims: [{ id, statement, evidence? }],
//   lenses?: ["correctness", "completeness", "reproducibility"],   // pick lenses for HOW this can fail
//   threshold?: majority of lenses,   // votes needed to UPHOLD
//   casting?: { verification?: {model?, effort} },
// }

const claims = (args && args.claims) || []
if (!claims.length) return { verdicts: [], note: 'no claims passed' }

const lenses = (args && args.lenses) || ['correctness', 'completeness', 'reproducibility']
const threshold = (args && args.threshold) || Math.floor(lenses.length / 2) + 1
const cast = ((args && args.casting) || {}).verification || {}
const verification = { effort: 'high', ...cast }

const VOTE = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } },
}

const verdicts = (await pipeline(claims, claim =>
  parallel(
    lenses.map(lens => () =>
      agent(
        `Try to REFUTE this claim through the ${lens} lens only.\nClaim [${claim.id}]: ${claim.statement}\n${claim.evidence ? `Evidence offered: ${claim.evidence}` : 'No evidence offered — weigh that.'}\nInspect real artifacts (code, tests, files, output) — never accept the claim's own wording as evidence. Default to refuted=true if uncertain.`,
        { label: `refute:${claim.id}:${lens}`, phase: 'Verify', effort: verification.effort, ...(verification.model ? { model: verification.model } : {}), schema: VOTE }
      )
    )
  ).then(votes => {
    const counted = votes.map((v, i) => (v ? { lens: lenses[i], ...v } : null)).filter(Boolean)
    const upholds = counted.filter(v => !v.refuted).length
    return {
      id: claim.id,
      upheld: upholds >= threshold && counted.length === lenses.length, // a missing vote never counts toward upholding
      votes: counted,
    }
  })
)).filter(Boolean)

const upheldCount = verdicts.filter(v => v.upheld).length
log(`${upheldCount}/${verdicts.length} claims upheld (threshold ${threshold}/${lenses.length})`)
return { verdicts }
