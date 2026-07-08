export const meta = {
  name: 'milestone-fanout',
  description: 'Drain ONE milestone in one invocation: a reasoning agent builds the dependency graph, code validates and schedules waves, coding lanes execute in parallel, an integrator merges serially — until the milestone is drained or safely stuck',
  phases: [
    { title: 'Graph', detail: 'reasoning agent proposes hard-dependency + conflict edges; code validates (cycles, unknown ids)' },
    { title: 'Waves', detail: 'per wave: parallel lanes → adversarial verify → serial integrate (merge + board Done)' },
  ],
}

// Reference implementation of dynamic-workflow-design.md — the ENVELOPE orchestrator.
//   Scope:        one MILESTONE per invocation. The milestone contract (goal + verdict question + anti-goals +
//                 acceptance, red-teamed at the pm gate) is the largest scope where "the design is trustworthy"
//                 holds — so one expensive invocation is allowed to carry the whole envelope, never more.
//   Shape:        graph → waves. The reasoning model PROPOSES the dependency graph; deterministic code VALIDATES
//                 it (unknown ids, cycles — one repair round) and schedules waves from it. Model judgment where
//                 judgment is needed, code where correctness is checkable.
//   Dependencies: hard edges (A before B) order the waves; conflict edges (same modules) keep two cards out of
//                 the same wave batch. Within a batch, lanes are independent → parallel.
//   Uncertainty:  each lane's "done" claim → one adversarial verifier per lane; merge = only verified lanes.
//   Casting:      graph/repair = reasoning (inherit main, xhigh) · lanes = coding (sonnet·xhigh) ·
//                 verify = verification (inherit, high) · integrate = coding (mechanical git/gh + board updates;
//                 the merge DECISION was already made by the verifier).
//   Budget:       waves ≤ maxWaves (default: card count = worst-case serial), stop under token floor,
//                 failed cards block their dependents (reported as leftovers, never retried blind).
//
// args: {
//   repo: "owner/name",
//   milestone: { title, goal, verdictQuestion?, acceptance? },
//   cards: [{ number, title, goalLink, acceptance, e2e?, dependsOn?: [numbers] }],   // ALL open cards of the milestone
//   maxLanes?: 2,               // per-wave parallelism (config.worktree.max_lanes)
//   maxWaves?: cards.length,
//   casting?: { coding?: {model,effort}, verification?: {model?,effort}, reasoning?: {model?,effort} },
// }

const cards = (args && args.cards) || []
if (!cards.length) return { merged: [], leftovers: [], drained: true, note: 'no open cards — milestone already drained' }

const repo = (args && args.repo) || ''
const ms = (args && args.milestone) || { title: '(unnamed)' }
const maxLanes = (args && args.maxLanes) || 2
const maxWaves = (args && args.maxWaves) || cards.length
const cast = (args && args.casting) || {}
const coding = { model: 'sonnet', effort: 'xhigh', ...(cast.coding || {}) }
const verification = { effort: 'high', ...(cast.verification || {}) }
const reasoning = { effort: 'xhigh', ...(cast.reasoning || {}) }

const GRAPH = {
  type: 'object',
  required: ['hard', 'conflict'],
  properties: {
    hard: { type: 'array', items: { type: 'object', required: ['before', 'after', 'reason'], properties: { before: { type: 'number' }, after: { type: 'number' }, reason: { type: 'string' } } } },
    conflict: { type: 'array', items: { type: 'object', required: ['a', 'b', 'reason'], properties: { a: { type: 'number' }, b: { type: 'number' }, reason: { type: 'string' } } } },
    notes: { type: 'string' },
  },
}
const LANE = {
  type: 'object',
  required: ['status', 'summary'],
  properties: {
    status: { enum: ['ready', 'failed', 'parked'] },
    branch: { type: 'string' }, pr: { type: 'number' }, evidencePath: { type: 'string' },
    summary: { type: 'string' }, blockReason: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object', required: ['upheld', 'reasons'],
  properties: { upheld: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } } },
}
const INTEGRATE = {
  type: 'object', required: ['merged', 'skipped'],
  properties: {
    merged: { type: 'array', items: { type: 'number' } },
    skipped: { type: 'array', items: { type: 'object', required: ['number', 'reason'], properties: { number: { type: 'number' }, reason: { type: 'string' } } } },
  },
}

// ── Graph: the reasoning model proposes; code validates ─────────────────────────────
phase('Graph')
const ids = new Set(cards.map(c => c.number))
const cardBrief = cards.map(c => ({ number: c.number, title: c.title, acceptance: c.acceptance, dependsOn: c.dependsOn || [] }))

const graphPrompt = extra =>
  `Build the execution dependency graph for milestone "${ms.title}" of repo ${repo}.
Milestone goal: ${ms.goal || '(see cards)'}
Cards (all open work of this milestone): ${JSON.stringify(cardBrief)}
Inspect the actual repo layout to ground your judgment (which modules/files each card will touch).
Return TWO edge sets:
- hard: {before, after} — "after" cannot start until "before" is MERGED (API before consumer, schema before query, board Depends-on, …). Only real prerequisites — a needless hard edge serializes the milestone.
- conflict: {a, b} — order-free, but they will edit the same modules/files, so they must not run in the same parallel wave.
Board Depends-on values are already included per card in dependsOn — fold them in as hard edges too. Use only the card numbers given.${extra || ''}`

const validate = g => {
  if (!g) return 'graph agent returned nothing'
  const bad = []
  for (const e of g.hard) if (!ids.has(e.before) || !ids.has(e.after) || e.before === e.after) bad.push(`hard ${e.before}->${e.after}`)
  for (const e of g.conflict) if (!ids.has(e.a) || !ids.has(e.b) || e.a === e.b) bad.push(`conflict ${e.a}|${e.b}`)
  if (bad.length) return `unknown/self card ids: ${bad.join(', ')}`
  // cycle check on hard edges (Kahn)
  const indeg = new Map(), adj = new Map()
  for (const n of ids) { indeg.set(n, 0); adj.set(n, []) }
  for (const e of g.hard) { adj.get(e.before).push(e.after); indeg.set(e.after, indeg.get(e.after) + 1) }
  const q = [...ids].filter(n => indeg.get(n) === 0)
  let seen = 0
  while (q.length) { const n = q.shift(); seen++; for (const m of adj.get(n)) { indeg.set(m, indeg.get(m) - 1); if (indeg.get(m) === 0) q.push(m) } }
  if (seen !== ids.size) return 'hard edges contain a cycle'
  return null
}

let graph = await agent(graphPrompt(), { label: 'dep-graph', phase: 'Graph', effort: reasoning.effort, ...(reasoning.model ? { model: reasoning.model } : {}), schema: GRAPH })
let err = validate(graph)
if (err) {
  log(`graph invalid (${err}) — one repair round`)
  graph = await agent(graphPrompt(`\n\nYour previous graph was rejected by the validator: ${err}. Fix exactly that.`), { label: 'dep-graph:repair', phase: 'Graph', effort: reasoning.effort, ...(reasoning.model ? { model: reasoning.model } : {}), schema: GRAPH })
  err = validate(graph)
}
if (err) {
  // Fail safe, not blind: no trustworthy graph → serial order (board order), zero parallelism assumptions.
  log(`graph still invalid (${err}) — falling back to fully serial execution`)
  graph = { hard: cards.slice(1).map((c, i) => ({ before: cards[i].number, after: c.number, reason: 'serial fallback' })), conflict: [] }
}
// fold board Depends-on in deterministically (the model was asked to, but the board is authoritative)
for (const c of cards) for (const d of c.dependsOn || []) if (ids.has(d)) graph.hard.push({ before: d, after: c.number, reason: 'board Depends-on' })
if (validate(graph)) return { merged: [], leftovers: cards.map(c => ({ card: c.number, reason: 'board Depends-on cycle — fix the board' })), drained: false }

const prereqs = new Map([...ids].map(n => [n, new Set()]))
for (const e of graph.hard) prereqs.get(e.after).add(e.before)
const conflicts = new Set(graph.conflict.flatMap(e => [`${e.a}|${e.b}`, `${e.b}|${e.a}`]))
log(`graph: ${graph.hard.length} hard · ${graph.conflict.length} conflict edges over ${cards.length} cards`)

// ── Waves: schedule deterministically, execute, integrate, repeat ────────────────────
phase('Waves')
const state = new Map(cards.map(c => [c.number, 'pending'])) // pending | merged | failed | parked | skipped
const byNum = new Map(cards.map(c => [c.number, c]))
const mergedAll = []
let wave = 0

while (wave < maxWaves) {
  if (budget.total && budget.remaining() < 40000) { log(`token floor reached (${Math.round(budget.remaining() / 1000)}k left) — stopping before wave ${wave + 1}`) ; break }
  const runnable = [...state].filter(([n, s]) => s === 'pending' && [...prereqs.get(n)].every(p => state.get(p) === 'merged')).map(([n]) => n)
  if (!runnable.length) break
  // greedy batch: no two conflicting cards in one wave, at most maxLanes
  const batch = []
  for (const n of runnable) {
    if (batch.length >= maxLanes) break
    if (batch.every(b => !conflicts.has(`${n}|${b}`))) batch.push(n)
  }
  wave++
  log(`wave ${wave}: cards ${batch.map(n => '#' + n).join(', ')} (${runnable.length - batch.length} runnable deferred)`)

  const results = (await pipeline(
    batch.map(n => byNum.get(n)),
    card =>
      agent(
        `You are one coding lane of repo ${repo}, executing board card #${card.number}: "${card.title}" (milestone "${ms.title}").
Goal-link: ${card.goalLink || '(missing — if truly absent on the card, stop and return status=parked)'}
Acceptance criteria:\n${card.acceptance}
${card.e2e ? `E2E scenario:\n${card.e2e}` : ''}
Work entirely inside your isolated worktree (it branches from fresh origin/${'{default}'} — prior waves are already merged in). Protocol:
1. TDD — failing test first (Red), implement (Green), refactor. Atomic commits; commit/PR text in plain product language, never naming any tool, agent, or automation.
2. Repo quality gates (format · lint · typecheck · tests + coverage) all green.
3. Push the branch and open a PR (do NOT merge — merging is serialized by the integrator).
4. Pre-merge production E2E on a lane-isolated port; evidence to e2e/reports/ with an explicit **PASS**/**FAIL** marker.
Return status=ready only if gates green AND E2E **PASS** AND PR open. Blocked → status=parked + blockReason. Never claim what you did not observe.`,
        { label: `lane:#${card.number}`, phase: 'Waves', model: coding.model, effort: coding.effort, isolation: 'worktree', schema: LANE }
      ),
    (lane, card) => {
      if (!lane || lane.status !== 'ready') return { card: card.number, lane, verdict: null }
      return agent(
        `Adversarially verify a completion claim in repo ${repo}. Card #${card.number}: "${card.title}".
Acceptance criteria:\n${card.acceptance}
The lane claims: ${lane.summary} (branch ${lane.branch || '?'}, PR #${lane.pr || '?'}, evidence ${lane.evidencePath || '?'}).
Try to REFUTE it: inspect the diff read-only, check every acceptance criterion against actual code/tests, read the E2E evidence for a real **PASS**. Default to upheld=false if uncertain.`,
        { label: `verify:#${card.number}`, phase: 'Waves', effort: verification.effort, ...(verification.model ? { model: verification.model } : {}), schema: VERDICT }
      ).then(v => ({ card: card.number, lane, verdict: v }))
    }
  )).filter(Boolean)

  for (const r of results) state.set(r.card, r.lane ? (r.lane.status === 'ready' ? 'pending' : r.lane.status) : 'failed')
  const verified = results.filter(r => r.lane && r.lane.status === 'ready' && r.verdict && r.verdict.upheld)
  const refuted = results.filter(r => r.lane && r.lane.status === 'ready' && !(r.verdict && r.verdict.upheld))
  for (const r of refuted) { state.set(r.card, 'failed'); log(`#${r.card} refuted by verifier: ${(r.verdict && r.verdict.reasons || []).join('; ') || 'no verdict'}`) }

  if (verified.length) {
    // ONE integrator agent per wave = merge serialization enforced by structure, not by prompt.
    const integ = await agent(
      `You are the integrator for repo ${repo}, wave ${wave} of milestone "${ms.title}". Merge these verified lanes ONE AT A TIME, in this order: ${JSON.stringify(verified.map(v => ({ number: v.card, branch: v.lane.branch, pr: v.lane.pr, evidencePath: v.lane.evidencePath })))}.
For each, sequentially: update the branch onto current origin default if needed (trivial conflicts only — anything non-trivial: skip with reason, do NOT improvise a resolution) → squash-merge the PR → confirm the default branch still builds/tests → move the board card to Done with the E2E evidence path and a short completion comment in plain product language (board writes via ${'`bash "$CLAUDE_PLUGIN_ROOT/scripts/board.sh"`'} status/evidence — never raw graphql). If a merge breaks the default branch, revert it and skip that card with the reason. Report exactly what merged and what was skipped.`,
      { label: `integrate:wave${wave}`, phase: 'Waves', model: coding.model, effort: coding.effort, schema: INTEGRATE }
    )
    const okSet = new Set((integ && integ.merged) || [])
    for (const v of verified) {
      if (okSet.has(v.card)) { state.set(v.card, 'merged'); mergedAll.push(v.card) }
      else { state.set(v.card, 'failed'); const why = ((integ && integ.skipped) || []).find(s => s.number === v.card); log(`#${v.card} not merged: ${(why && why.reason) || 'integrator gave no result'}`) }
    }
  }
}

// classify leftovers (never retried blind — the main loop / approval queue owns them)
const leftovers = []
for (const [n, s] of state) {
  if (s === 'merged') continue
  const blockedBy = [...prereqs.get(n)].filter(p => state.get(p) !== 'merged')
  leftovers.push({ card: n, reason: s !== 'pending' ? s : blockedBy.length ? `blocked by unmerged ${blockedBy.map(x => '#' + x).join(',')}` : 'not reached (wave/budget cap)' })
}
const drained = leftovers.length === 0
log(`milestone "${ms.title}": ${mergedAll.length}/${cards.length} merged over ${wave} wave(s)${drained ? ' — drained' : ` — ${leftovers.length} left`}`)
// The milestone close-out (verdict question, human judgment) stays with the main loop — this returns data.
return { merged: mergedAll, leftovers, waves: wave, drained }
