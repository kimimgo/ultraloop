export const meta = {
  name: 'pm-chain',
  description: 'Mission → strategy perspectives → north-star draft → red-team barrier → per-milestone spec → prioritized board plan (data only; pm writes the board)',
  phases: [
    { title: 'Strategy', detail: 'independent perspectives (casting: reasoning)' },
    { title: 'North star', detail: 'goal-chain synthesis' },
    { title: 'Red team', detail: 'adversarial assumption attack — a BARRIER: no spec entry without passing' },
    { title: 'Spec', detail: 'milestone contracts + seed cards' },
    { title: 'Prioritize' },
  ],
}

// Reference implementation of dynamic-workflow-design.md §0–§2.
//   Shape:        strategy → north star → red team → spec → prioritize; every stage returns structured JSON.
//   Dependencies: strategy perspectives are independent BUT synthesis needs ALL of them → a justified barrier.
//                 Red team is the second justified barrier: spec entry is forbidden until kill criteria pass.
//                 Spec-per-milestone is independent again → pipeline.
//   Uncertainty:  the plan's load-bearing assumptions → the red-team stage, with one bounded revision round.
//   Casting:      every stage here is reasoning/judgment → model omitted (inherits the main session), xhigh.
//   Budget:       fixed stage count; the only loop (revise→re-attack) is capped at 1 round in code.
//
// args: { mission, repo, context?, perspectives?: ["mvp-first","risk-first","user-first"] }
//
// Output is a PLAN (data). The pm skill registers it on the board via its own scripts — this workflow
// never writes the board, keeping board authority in one place.

const mission = (args && args.mission) || ''
if (!mission) return { status: 'error', note: 'args.mission required' }
const repo = (args && args.repo) || ''
const context = (args && args.context) || ''
const perspectives = (args && args.perspectives) || ['mvp-first', 'risk-first', 'user-first']

const STRATEGY = {
  type: 'object',
  required: ['thesis', 'segments', 'tradeoffs', 'risks'],
  properties: {
    thesis: { type: 'string' },
    segments: { type: 'array', items: { type: 'string' } },
    tradeoffs: { type: 'array', items: { type: 'string' } },
    risks: { type: 'array', items: { type: 'string' } },
  },
}
const PLAN = {
  type: 'object',
  required: ['northStar', 'indicators', 'antiGoals', 'milestones'],
  properties: {
    northStar: { type: 'string' },
    indicators: { type: 'array', items: { type: 'string' }, maxItems: 3 },
    antiGoals: { type: 'array', items: { type: 'string' }, maxItems: 3 },
    milestones: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'goal', 'verdictQuestion'],
        properties: {
          title: { type: 'string' },
          goal: { type: 'string' },
          verdictQuestion: { type: 'string' },
          northStarContribution: { type: 'string' },
        },
      },
    },
  },
}
const ATTACK = {
  type: 'object',
  required: ['fatal', 'findings', 'killCriteria'],
  properties: {
    fatal: { type: 'boolean' },
    findings: { type: 'array', items: { type: 'string' } },
    killCriteria: { type: 'array', items: { type: 'string' } },
  },
}
const SPEC = {
  type: 'object',
  required: ['milestone', 'acceptance', 'seedCards'],
  properties: {
    milestone: { type: 'string' },
    acceptance: { type: 'array', items: { type: 'string' } },
    seedCards: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'goalLink', 'acceptance', 'e2e'],
        properties: {
          title: { type: 'string' },
          goalLink: { type: 'string' },
          acceptance: { type: 'string' },
          e2e: { type: 'string' },
          dependsOn: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
}
const RANKED = {
  type: 'object',
  required: ['order'],
  properties: {
    order: { type: 'array', items: { type: 'object', required: ['title', 'score', 'rationale'], properties: { title: { type: 'string' }, score: { type: 'number' }, rationale: { type: 'string' } } } },
  },
}

phase('Strategy')
// Barrier justified: north-star synthesis must compare ALL perspectives against each other.
const views = (await parallel(
  perspectives.map(p => () =>
    agent(
      `Build a product strategy for this mission from a strictly ${p} perspective.\nMission: ${mission}\n${context ? `Context: ${context}` : ''}\nBe opinionated; surface the trade-offs the other perspectives would hide.`,
      { label: `strategy:${p}`, phase: 'Strategy', effort: 'xhigh', schema: STRATEGY }
    )
  )
)).filter(Boolean)
if (!views.length) return { status: 'error', note: 'all strategy perspectives failed' }

phase('North star')
let plan = await agent(
  `Synthesize these ${views.length} strategy perspectives into one goal chain for the mission.\nMission: ${mission}\nPerspectives: ${JSON.stringify(views)}\nProduce: ONE measurable north-star sentence (whose day changes, how — measurable), ≤3 leading indicators, ≤3 anti-goals (scope lines we will NOT cross), and milestones as STATE TRANSITIONS toward the north star (never feature bundles), each with a goal sentence ("when done, [the user] can [what]") and a Yes/No verdict question.`,
  { label: 'north-star', phase: 'North star', effort: 'xhigh', schema: PLAN }
)
if (!plan) return { status: 'error', note: 'north-star synthesis failed' }

phase('Red team')
// The barrier: no spec entry until the attack passes. One bounded revision round, then escalate.
const lenses = ['demand (does anyone need this?)', 'feasibility (can this team ship it?)', 'scope-drift (which milestone will silently balloon?)']
const attack = async p =>
  (await parallel(
    lenses.map(l => () =>
      agent(
        `Attack this plan through the lens of ${l}. Steelman it first, then attack the load-bearing assumptions. For each: the cheapest test and a kill criterion. fatal=true only if a load-bearing assumption fails with no cheap test to save it.\nMission: ${mission}\nPlan: ${JSON.stringify(p)}`,
        { label: `red-team:${l.split(' ')[0]}`, phase: 'Red team', effort: 'xhigh', schema: ATTACK }
      )
    )
  )).filter(Boolean)

let attacks = await attack(plan)
if (attacks.some(a => a.fatal)) {
  log('red team found fatal assumptions — one revision round')
  const revised = await agent(
    `Revise this plan to survive the red-team findings without inflating scope (respect the anti-goals; shrinking is allowed, padding is not).\nPlan: ${JSON.stringify(plan)}\nFindings: ${JSON.stringify(attacks)}`,
    { label: 'revise', phase: 'Red team', effort: 'xhigh', schema: PLAN }
  )
  if (revised) plan = revised
  attacks = await attack(plan)
  if (attacks.some(a => a.fatal))
    return { status: 'blocked', reason: 'red team fatal after one revision — human scope decision needed', plan, attacks }
}

phase('Spec')
const specs = (await pipeline(plan.milestones, m =>
  agent(
    `Write the milestone contract + seed cards for milestone "${m.title}" of repo ${repo}.\nMilestone goal: ${m.goal}\nVerdict question: ${m.verdictQuestion}\nNorth star: ${plan.northStar}\nAnti-goals: ${JSON.stringify(plan.antiGoals)}\nRed-team kill criteria to respect: ${JSON.stringify(attacks.flatMap(a => a.killCriteria))}\nSeed cards = only the load-bearing ones (the loop breeds tactical TDD cards inside the envelope later). Every card: a one-line Goal-link to this milestone's goal (no link = not a card), checkable acceptance criteria, and a human-style E2E scenario. Plain product language only.`,
    { label: `spec:${m.title.slice(0, 24)}`, phase: 'Spec', effort: 'xhigh', schema: SPEC }
  )
)).filter(Boolean)

phase('Prioritize')
const allCards = specs.flatMap(s => s.seedCards.map(c => ({ ...c, milestone: s.milestone })))
const ranked = await agent(
  `Prioritize these seed cards with RICE (fall back to ICE where reach is unknowable). Score against the north star, not against feature excitement.\nNorth star: ${plan.northStar}\nCards: ${JSON.stringify(allCards)}`,
  { label: 'prioritize', phase: 'Prioritize', effort: 'high', schema: RANKED }
)

return { status: 'ok', plan, attacks, specs, priorities: (ranked && ranked.order) || [] }
