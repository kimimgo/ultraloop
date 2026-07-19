# Skill invocation — the invocation contract (v0.13 M2)

> ultraloop's power comes from *composing proven sub-skills*, not reimplementing them. But composition only
> pays off if the sub-skills actually fire. Natural-language auto-triggering does not deliver that: measured
> recall of a sub-skill firing from prose is ~0. This file is the contract that makes invocation reliable —
> read it before running any orchestrator (pm · design · loop). It defines the 1% rule, the per-stage
> fan-out map, and the loud-fallback discipline that replaces silent degrade.

## The 1% invocation rule (never silent-degrade)

ultraloop's orchestrators (pm · design · loop) do NOT rely on a sub-skill auto-triggering from natural language — measured trigger rate is ~0. Instead:

1. **Call by exact name.** For each stage, invoke the mapped sub-skill by its exact name via the Skill tool. The per-stage fan-out map is authoritative; it is not optional.
2. **1% → fire.** If a stage is even 1% relevant to the work in hand, fire its mapped skill. Never skip on a weak excuse ("probably not needed", "too small"). Skipping is the failure mode this rule kills.
3. **Verify it ran.** After the call, confirm the skill actually executed and returned usable output.
4. **Fail loud, never silent.** If it did not run / is absent / returned nothing usable, say so explicitly and either (a) fall back to the built-in path and STATE the fallback, or (b) stop with a clear reason. A silent degrade to solo behavior is forbidden — it is exactly how "the skills never fire" happened.
5. **Lean, not bloated.** Only cherry-picked essentials are bundled; the rest are called by name and, if absent, trigger the loud fallback. Small plugin, guaranteed invocation.

## Fan-out (dependent = sequential; independent = parallel — see workflow-tool-spec.md)

- **pm** (planner): discovery = [opportunity-solution-tree · (identify-assumptions → prioritize-assumptions) · brainstorming] IN PARALLEL → product-strategy → north-star lock-in → risk = [strategy-red-team · pre-mortem] IN PARALLEL (red-team is the barrier: no spec entry without passing) → outcome-roadmap → prioritization-frameworks → speckit → **gh-roadmap** (board write). Output = north-star + SEED cards only.
- **design** (per card): [imgyu-techdoc → artifacts-ops publish] IN PARALLEL WITH [card-planning]; attach design URL to the card's Design-Doc field and the plan to the issue body.
- **loop** (engine): per Ready card → **design** (invoke) → build [superpowers chain — BARRIER] → parallel waves [milestone-fanout / lane-fanout] → E2E → **gh-roadmap** (status).

## Bundled vs referenced — and the fallback for each absent skill

Each orchestrator ships a lean set of **bundled** sub-skills (always present in the plugin) and **references**
the rest by exact name. A referenced skill that is absent at call time triggers the loud fallback below — never
a silent skip.

| Orchestrator | Bundled (always present) | Referenced by name | Fallback if a referenced skill is absent |
| --- | --- | --- | --- |
| **pm** | pm-chain, gh-roadmap, opportunity-solution-tree, identify-assumptions, prioritize-assumptions, brainstorming, pre-mortem | product-strategy, strategy-red-team, outcome-roadmap, prioritization-frameworks, speckit | State the gap loudly, then run the built-in inline planning path for that stage — EXCEPT strategy-red-team: it is the barrier, so if absent, STOP (no spec entry without a passing red-team). |
| **design** | card-planning | imgyu-techdoc, artifacts-ops | State the gap; on imgyu-techdoc absent, author a plain-markdown design doc inline; on artifacts-ops absent, attach the doc to the issue/card directly instead of a published URL, and say so. |
| **loop** | loop, gh-roadmap, milestone-fanout, lane-fanout, adversarial-verify | design (orchestrator); superpowers:test-driven-development, superpowers:systematic-debugging, superpowers:requesting/receiving-code-review, superpowers:verification-before-completion, superpowers:finishing-a-development-branch | superpowers is a BARRIER like strategy-red-team: absent → STOP (doctor ✗, bootstrap ✗, lane returns parked). No built-in TDD fallback anymore. (design-absent still blocks the card, unchanged.) |

---

Closing note: each orchestrator SKILL (pm · design · loop) MUST open by pointing to this file. Its first move
is to load `references/skill-invocation.md`, adopt the 1% invocation rule, and drive its stages through the
fan-out map above — calling every mapped sub-skill by exact name, verifying each ran, and failing loud (never
silent) on any absence. This is the single contract that keeps ultraloop a lean composer of proven skills
rather than a solo agent that quietly reinvents them.
