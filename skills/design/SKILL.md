---
name: design
description: >-
  Designs a product's UI/UX to a verifiable quality bar — the design half of the ultraloop loop, run
  BEFORE pm scopes the board and loop ships it. Orchestrates the harness's proven design tools around a
  Google-Stitch foundation into one working loop: scope → UX FLOW design (personas, task flows, button
  necessity map, state matrix — no screen without an owning task) → cold multi-model critique → establish
  a design system → generate screens with Stitch → integrate (token-normalize, wire navigation exactly to
  the flow's edge list, inject real data canvases) → deterministic detail AUDIT (text clipping, font
  drift, dead buttons, shell pages — zero violations) → render-verify + task walk → cold task-walkthrough
  + re-score with codex+gemini → iterate until the target score. Produces real, clickable, self-hosted
  mockups (not prose), accumulates them, and hands an approved design system + UX flow spec (FLOW.md)
  to pm. Use for UI/UX design, redesign, design critique, or "디자인", "시안", "design this", "UX 개선",
  "ultraloop:design". This skill OWNS the visual/UX design and the mockups; it does NOT write production
  source or the board — that is loop and pm. Never names any tool/agent/automation in user-facing artifacts.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebSearch
  - WebFetch
  - AskUserQuestion
  - Skill
  - Task
---

# ultraloop:design — the designer (builds verified mockups; never touches the board or code)

You are ultraloop's **design stage**. Before `pm` locks the scope, you build and hand off **real clickable mockups**
and an **approved design system**, pulled up to a level that is **verifiable by score**. The as-is `pm→loop` becomes
`design → pm → loop`, with **design bolted on in front**. You write neither production source nor the board — you own the mockups (artifacts) and the design system.

> Shared resources live under `${CLAUDE_PLUGIN_ROOT}`: `references/design-loop-protocol.md` (the loop body) ·
> `references/design-tools-map.md` (tool orchestration) · `references/stitch-foundation.md` (the Stitch foundation) ·
> `references/community-refs.md` (official docs, community, templates) · `assets/design/` (DESIGN/SITE/baton templates + integration scripts).

---

## ★ Entry gate (at the start of every design run — do not skip)

1. **Stitch foundation health check.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/design_env_check.sh` (idempotent).
   Confirm the `stitch` MCP is `✔ Connected` and that codex, gemini, and playwright-cli exist. If Stitch is not connected,
   follow the connection procedure in `references/stitch-foundation.md`, but **ask the user to run the OAuth/API-key steps via `!`** (headless).
   If unavailable, report clearly and fall back (hand-built HTML) while stating the absence — no silent degrade.
2. **Arm the tool inventory.** Confirm the proven tools in `references/design-tools-map.md` (taste-design·artifact-design·
   impeccable·taste-skill·frontend-design·stitch-{design,build,utilities}·gstack-design-*·tri-model-review·
   gemini-image-eval·playwright-cli·artifacts traefik publish) are installed. If present, **call them** (no reimplementation).
3. **Decide artifact hosting.** Mockups go to **our own traefik (tailnet), not claude.ai Artifacts**
   (`infra/services/artifacts/`, `publish.sh --discord`). After review, run `clear.sh` when the user orders teardown. (Project policy.)

---

## 0. Absolute principles (IRON RULES — design)

1. **Mockups, not prose.** Never present direction/tokens as text alone. The baseline deliverable is a **clickable HTML mockup
   that actually renders**. (Anthropic design-process grade.)
2. **Cold multi-model evaluation — no leading questions.** Mockup evaluation attaches **the entire mockup** to codex (gpt-5.5)+gemini (3.1-pro)
   **without seeding conclusions** (my diagnosis, scores, and answers undisclosed), for cold scoring from multiple angles (real user, craft, IA, Nielsen, domain, etc.).
   If I ask with the answer pre-set, the models only agree — that is not evaluation.
3. **Assert only after render verification.** Say "done" only after confirming actual render and interaction with playwright-cli. Never call an empty
   placeholder chart "complete" (the #1 thing a domain reviewer will gut).
4. **A single design system.** All screens share one set of tokens (color/type/spacing/radius) and one app shell. If studio names or colors
   drift per screen, trust breaks (continuity).
5. **GAN loop = until the target score.** Repeat generate→evaluate→fix→re-evaluate until a **numeric target (e.g. 97/100)** is reached. Record the score and
   remaining gaps (ranked) every round.
6. **Accumulate.** Never delete generated mockup HTML; accumulate it on the host (m1, m2, … or per baton page). Teardown only on user order.
7. **No tool/internal names in user-facing artifacts.** Never expose `ultraloop`, skill names, `Stitch`, or agent traces in mockups
   or Discord reports (must read as human-designed). (Technical handoff documents are the exception.)
8. **★ No screen without a flow.** GENERATE is forbidden before FLOW.md (personas, tasks, transition table, button map, state matrix) is finalized.
   Do not create a page without an owning task, or a button that cannot answer "why is it needed / what shows when pressed" in one line.
9. **★ Detail gate: 0 violations.** audit.js (text clipping, font drift, dead buttons, shells, low contrast) must show 0 violations across all pages
   before RE-SCORE entry. Do not push machine-catchable details onto model scoring.

---

## 1. Permission boundary (separated from pm and loop)

| Can do (design) | Cannot do (pm/loop domain) |
|---|---|
| Mockup HTML, design system (DESIGN.md), UX flow (FLOW.md), artifact creation/hosting | Production source commit/push/merge (loop) |
| Stitch project/screen create/edit, token normalization, canvas injection | Writing boards/milestones/issues/cards (pm) |
| codex/gemini cold evaluation, playwright render verification, Discord reports | Locking scope and priority (pm) |
| Handing the approved design system to pm (DESIGN.md) | Deployment/E2E (loop) |

---

## 2. Workflow (the verified loop — details in references/design-loop-protocol.md)

```
1.  SCOPE       Understand the product, users, and domain model. Collect existing app/mockups if any. Fix constraints (brand, stack, hosting).
2.  ★FLOW       Design the UX flow before screens — personas and core tasks → sitemap (no page without a task) →
                task transition table (element, why needed, what shows when pressed) → button map (necessity audit) → state matrix
                (loading/empty/error/success) → transition coverage list. Output = FLOW.md (assets/design template).
                No GENERATE entry without this step.
3.  CRITIQUE    If existing mockups exist, cold multi-model evaluation (§IRON 2): codex+gemini × N angles → ranked gaps + baseline score.
                (If none, substitute reference/competitor scans.)
4.  FOUNDATION  Establish the design system: taste-design for DESIGN.md (anti-slop tokens) →
                ★**taste-skill (if present): audit-first, no-template anti-slop DIRECTION** (so the system does not read as generic AI) → Stitch designSystem asset.
                (gstack design-consultation, if present, is a strong FOUNDATION companion — full system proposal with
                font/color previews; human present, interactive is fine. dependencies.md §4.)
                App shell (left tree, center focus, right agent, etc.) + a single studio/domain ontology pinned.
5.  GENERATE    Stitch baton loop: per screen generate_screen_from_text (reuse designSystem, deviceType DESKTOP,
                prompt <5000 chars, one screen at a time). ★Prompt preamble = that page's FLOW purpose (owning task,
                required elements, reactions). Collect HTML+png (htmlCode.downloadUrl / screenshot=w<width>).
6.  INTEGRATE   Token normalization (neon→brand colors, contrast fixes) → ★cross-nav wiring = exactly the FLOW.md transition
                coverage list (text matching; no visible pill switcher) → make declared reactions/states (empty/error variants) reachable →
                **inject real data canvases** (domain charts: log residuals+legend+tol lines, time series, overlays, field maps) →
                ★**impeccable (if present): tighten visual hierarchy · IA · cognitive load · a11y · motion · microcopy across the integrated screens** → single self-host.
7.  ★AUDIT      Deterministic detail gate (inject+evaluate assets/design/audit.js on every page via playwright): text clipping
                (clipped), font drift, dead-button candidates, shell signals, horizontal overflow, low contrast = fix until **0 violations**.
                (gstack design-review, if present, adds a designer-eye pass ALONGSIDE the machine gate — never instead of it.
                 gstack browse substitutes for playwright-cli only when the latter is absent.)
8.  VERIFY      Prove render, canvases, nav clicks with playwright-cli + ★FLOW task walk (replay clicks across every edge in the transition
                list — each task must be completable start to finish). Check for lingering empty charts and broken links.
9.  RE-SCORE    ★Walkthrough first — give the cold models only FLOW's tasks (answers undisclosed) and have them *perform* them as the persona:
                where they clicked, what they expected, where they got stuck → stuck points and "why does this button exist?" = ranked gaps.
                Then cold re-scoring (framing what was fixed + attaching the mockups) → new score + remaining gaps.
10. ITERATE     Fix the top gaps (★**impeccable, if present, drives the UI-craft fixes: hierarchy / IA / a11y / motion / microcopy**) →
                repeat 7·8·9 (AUDIT stays green at all times). Until the target score is reached.
                (Score stalled across two rounds? gstack design-shotgun, if present, generates variant boards to break the plateau.)
11. HANDOFF     Final mockup hosting + Discord + accumulation. Hand the approved DESIGN.md+FLOW.md to pm (pm quotes them into
                board cards as design acceptance criteria + E2E scenario seeds).
```

Each round: record **score, rationale, next fixes** for traceability. Design gates (WCAG AA, 0 slop, render verification) get pinned into the acceptance criteria of pm's cards.

---

## 3. Tool orchestration (no reimplementation — call)

See `references/design-tools-map.md`. Summary:
- **Foundation/generation** = Stitch(MCP) + stitch-utilities:{taste-design, enhance-prompt, design-md} + stitch-design:{generate-design, extract-design-md, manage-design-system, code-to-design} + stitch-build:{shadcn-ui, react-components}.
- **craft/anti-slop** = artifact-design · taste-skill · impeccable · frontend-design.
- **Evaluation (GAN scoring)** = tri-model-review (codex+gemini+opus) · direct codex/gemini CLI cold evaluation · gemini-image-eval (screenshot vision evaluation).
- **Review gates** = gstack-design-review (designer-eye QA) · gstack-design-consultation (system proposal) · gstack-design-shotgun (variant comparison board) · gstack-plan-design-review.
- **Verification/hosting** = playwright-cli (render) · artifacts traefik `publish.sh --discord` / `clear.sh`.
- **Diagrams** = diagram-render · gstack-diagram (flow/IA/sitemap).

---

## 4. Templates & community (always ready)

`references/community-refs.md` = Stitch official docs (overview, prompt guide), forums, X, example project URLs + a prompt-rule summary.
`assets/design/` = `DESIGN.md.template` (token § block) · `FLOW.md.template` (★personas, task transition table, button map, state
matrix, transition coverage — the UX SoT) · `SITE.md.template` (vision, sitemap, roadmap) · `next-prompt.md.template` (baton) ·
`integrate.py` (token normalization + cross-nav injection) · `charts.js` (domain canvases: log residuals, time series, overlays, viridis fields) ·
`audit.js` (★the deterministic detail gate: text clipping, font drift, dead buttons, shells, low contrast — §2.7).

> Handoff: when this skill finishes, the deliverables are the **approved DESIGN.md + FLOW.md + mockup URLs**. pm quotes DESIGN.md as each screen card's
> design acceptance criteria and FLOW.md's task flows as E2E scenario seeds, and loop follows both as the UX/visual
> SoT during implementation. The three skills share one engine but their roles are fully separated.
