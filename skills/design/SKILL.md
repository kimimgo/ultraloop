---
name: design
description: >-
  Designs a product's UI/UX to a verifiable quality bar — the design half of ultraloop, run before pm
  scopes the board. Runs one loop: scope → UX flow design (personas, task flows, a button-necessity map,
  a state matrix) → cold multi-model critique → a shared design system → screen generation on a
  Google-Stitch foundation → integrate → a deterministic detail audit (text clipping, font drift, dead
  buttons) → render-verify + task walk → re-score, iterating until a target score. Produces real,
  clickable, self-hosted mockups (not prose) and hands an approved design system plus a UX flow spec
  (FLOW.md) to pm. Use for UI/UX design, redesign, or design critique — "디자인", "시안", "design this",
  "UX 개선", "ultraloop:design". Owns the visual/UX design and mockups, not production source or the
  board (that is loop and pm). Never names any tool or agent in user-facing artifacts.
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

> **TL;DR** — design the UI/UX to a verified score and produce real clickable mockups, then hand an approved DESIGN.md + FLOW.md to pm. You write neither the board nor production code.
> Invoked as `/ultraloop:design`, before pm scopes the board. **Do the Entry gate below first** (Stitch health check → arm the design tools → decide mockup hosting), then start at SCOPE/FLOW.

You are ultraloop's **design stage**. Before `pm` locks the scope, you build and hand off **real clickable mockups**
and an **approved design system**, pulled up to a level that is **verifiable by score**. The as-is `pm→loop` becomes
`design → pm → loop`, with **design bolted on in front**. You write neither production source nor the board — you own the mockups (artifacts) and the design system.

> Shared resources live under `${CLAUDE_PLUGIN_ROOT}`: `references/design-loop-protocol.md` (the loop body) ·
> `references/design-tools-map.md` (tool orchestration) · `references/stitch-foundation.md` (the Stitch foundation) ·
> `references/community-refs.md` (official docs, community, templates) · `assets/design/` (DESIGN/SITE/baton templates + integration scripts).

---

## Entry gate — do this before every design run (the rest of the loop assumes it's done)

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

## 0. Principles — why this loop holds together

These are the load-bearing habits. Each exists for a concrete reason, so keep the reason in mind rather than the rule alone.

1. **Ship mockups, not prose.** The deliverable is a clickable HTML mockup that actually renders — direction and tokens
   described in text can't be verified and don't clear the bar reviewers judge against. (Anthropic design-process grade.)
2. **Evaluate cold — no leading questions.** Attach the entire mockup to codex (gpt-5.5) + gemini (3.1-pro) *without* seeding
   your diagnosis, scores, or answers, and let them score from several angles (real user, craft, IA, Nielsen, domain).
   If you ask with the answer pre-set, the models just agree — that isn't evaluation.
3. **Assert only after render verification.** Say "done" only once playwright-cli confirms the real render and interaction.
   An empty placeholder chart called "complete" is the first thing a domain reviewer guts, so don't let one through.
4. **One design system.** Every screen shares one set of tokens (color/type/spacing/radius) and one app shell; when studio
   names or colors drift per screen, continuity — and trust — breaks.
5. **Iterate to the target score.** Repeat generate → evaluate → fix → re-evaluate until a numeric target (e.g. 97/100),
   recording the score and the ranked remaining gaps each round so progress stays visible and traceable.
6. **Accumulate.** Keep every generated mockup on the host (m1, m2, … or per baton page) and tear down only when the user
   asks — you lose comparison history the moment you delete.
7. **No tool or internal names in user-facing artifacts.** Mockups and Discord reports must read as human-designed, so
   `ultraloop`, skill names, `Stitch`, and agent traces stay out of them (technical handoff docs are the exception).
8. **No screen without a flow.** Don't enter GENERATE until FLOW.md (personas, tasks, transition table, button map, state
   matrix) is final. A page with no owning task — or a button that can't answer "why is it needed / what shows when
   pressed" in one line — is the dead weight the audit flags later, so catch it at design time.
9. **Detail gate: 0 violations before RE-SCORE.** audit.js catches machine-detectable defects (text clipping, font drift,
   dead buttons, shells, low contrast); clear them all first, so reviewers spend their judgment on the design, not typos.

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
2.  FLOW       Design the UX flow before screens — personas and core tasks → sitemap (no page without a task) →
                task transition table (element, why needed, what shows when pressed) → button map (necessity audit) → state matrix
                (loading/empty/error/success) → transition coverage list. Output = FLOW.md (assets/design template).
                No GENERATE entry without this step.
3.  CRITIQUE    If existing mockups exist, cold multi-model evaluation (§0.2): codex+gemini × N angles → ranked gaps + baseline score.
                (If none, substitute reference/competitor scans.)
4.  FOUNDATION  Establish the design system: taste-design for DESIGN.md (anti-slop tokens) →
                **taste-skill (if present): audit-first, no-template anti-slop DIRECTION** (so the system does not read as generic AI) → Stitch designSystem asset.
                (gstack design-consultation, if present, is a strong FOUNDATION companion — full system proposal with
                font/color previews; human present, interactive is fine. dependencies.md §4.)
                App shell (left tree, center focus, right agent, etc.) + a single studio/domain ontology pinned.
5.  GENERATE    Stitch baton loop: per screen generate_screen_from_text (reuse designSystem, deviceType DESKTOP,
                prompt <5000 chars, one screen at a time). Prompt preamble = that page's FLOW purpose (owning task,
                required elements, reactions). Collect HTML+png (htmlCode.downloadUrl / screenshot=w<width>).
6.  INTEGRATE   Token normalization (neon→brand colors, contrast fixes) → cross-nav wiring = exactly the FLOW.md transition
                coverage list (text matching; no visible pill switcher) → make declared reactions/states (empty/error variants) reachable →
                **inject real data canvases** (domain charts: log residuals+legend+tol lines, time series, overlays, field maps) →
                **impeccable (if present): tighten visual hierarchy · IA · cognitive load · a11y · motion · microcopy across the integrated screens** → single self-host.
7.  AUDIT      Deterministic detail gate (inject+evaluate assets/design/audit.js on every page via playwright): text clipping
                (clipped), font drift, dead-button candidates, shell signals, horizontal overflow, low contrast = fix until **0 violations**.
                (gstack design-review, if present, adds a designer-eye pass ALONGSIDE the machine gate — never instead of it.
                 gstack browse substitutes for playwright-cli only when the latter is absent.)
8.  VERIFY      Prove render, canvases, nav clicks with playwright-cli + FLOW task walk (replay clicks across every edge in the transition
                list — each task must be completable start to finish). Check for lingering empty charts and broken links.
9.  RE-SCORE    Walkthrough first — give the cold models only FLOW's tasks (answers undisclosed) and have them *perform* them as the persona:
                where they clicked, what they expected, where they got stuck → stuck points and "why does this button exist?" = ranked gaps.
                Then cold re-scoring (framing what was fixed + attaching the mockups) → new score + remaining gaps.
10. ITERATE     Fix the top gaps (**impeccable, if present, drives the UI-craft fixes: hierarchy / IA / a11y / motion / microcopy**) →
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
`assets/design/` = `DESIGN.md.template` (token § block) · `FLOW.md.template` (personas, task transition table, button map, state
matrix, transition coverage — the UX SoT) · `SITE.md.template` (vision, sitemap, roadmap) · `next-prompt.md.template` (baton) ·
`integrate.py` (token normalization + cross-nav injection) · `charts.js` (domain canvases: log residuals, time series, overlays, viridis fields) ·
`audit.js` (the deterministic detail gate: text clipping, font drift, dead buttons, shells, low contrast — §2.7).

> Handoff: when this skill finishes, the deliverables are the **approved DESIGN.md + FLOW.md + mockup URLs**. pm quotes DESIGN.md as each screen card's
> design acceptance criteria and FLOW.md's task flows as E2E scenario seeds, and loop follows both as the UX/visual
> SoT during implementation. The three skills share one engine but their roles are fully separated.
