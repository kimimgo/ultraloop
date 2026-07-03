# design-loop-protocol — the verified UI/UX GAN loop

The body of `ultraloop:design`. A flow→generate→audit→evaluate→fix→re-score loop driven to a numeric target.
Empirically validated 2026-06-23 (foamlab m11): a "color-copied" mockup scored 5/100 by the user and
35–58 by cold domain reviewers was rebuilt with this loop to codex 84 / gemini 92 in one generate+integrate
pass, then iterated upward by closing the ranked gaps.

Three failure classes this protocol exists to kill: **shell pages** (screens that exist but mean nothing),
**unwired affordances** (buttons that go nowhere), and **detail rot** (clipped labels, font drift, dead
contrast) — all three are caught by structure (FLOW), determinism (AUDIT), and simulation (WALKTHROUGH),
not by hoping the generator behaves.

## 1. SCOPE
- Understand the product, the real end-user, and the DOMAIN workflow (not an imagined one). Recover the
  true data model / task loops from source or prior art if they exist. Fix constraints: brand, stack,
  hosting (self-host traefik tailnet), accessibility (WCAG AA), device (DESKTOP first unless told).
- Output: a one-paragraph product truth + the canonical domain narrative (names/entities reused on EVERY
  screen — drift here is the #1 trust-killer reviewers flag).

## 2. FLOW (UX flow design — before any screen; GENERATE is forbidden without this step) ★
- Fill `assets/design/FLOW.md.template` → **FLOW.md** — the UX SoT that navigation wiring and the
  task-walk verification both consume:
  1. **Personas & core tasks** — who is doing what, success condition per task. A page exists only to
     serve a task; a page that owns no task is not designed.
  2. **Task-flow transition table** — per task: entry → action (element) → reaction (what becomes visible) → next. Every step
     names the element, the reaction, and the state (loading/empty/error/success).
  3. **Button map (necessity audit)** — every planned interactive element maps to a task. A button whose
     "why is it needed" cannot be written in one line is not added. Each button declares what pressing it shows.
  4. **State matrix** — page × {loading, empty, error, success}. Single-state design is a shell.
  5. **Transition coverage list** — the exact edge list INTEGRATE must wire and VERIFY must click.
- FLOW.md is reviewed with the user (or cold-modeled if unattended) BEFORE any screen is generated.
  This is where "filler shell (hollow) pages" die: pages/buttons enter the design only by owning a task.

## 3. CRITIQUE (cold, multi-model, NO leading) — only if a prior design exists
- Throw the FULL artifact (entire HTML) at codex(gpt-5.5 xhigh) AND gemini(3.1-pro). Give MINIMAL product
  context and NO diagnosis, NO target score, NO "right answer". Ask for an independent brutal critique + a
  /100 score + ranked concrete gaps.
- Run MULTIPLE ANGLES (separate calls, distinct personas): real end-user, pure visual craft (domain-blind),
  product/JTBD, Nielsen heuristics, IA/interaction model, and a DEEP DOMAIN-SPECIALIST lens. The domain lens
  is the harshest and most valuable — it exposes what only an expert catches.
- Why: if you bake your conclusion into the prompt, the models just agree. The user will (rightly) call it
  out. Diverse cold angles triangulate the real defect; convergence across them = signal.
- Output: a deduped, ranked gap list + a baseline score. (Holistic glance scores high; deep lenses score
  low — the gap between them IS the work.)

## 4. FOUNDATION
- Establish ONE design system: run taste-design → DESIGN.md (anti-slop tokens: surfaces, one cool + one warm
  accent <80% sat, status colors with icon+label, type scale weight-driven, spacing scale, 2 radii, no neon
  glow). Pin fonts (avoid Inter for premium). Create/normalize a Stitch designSystem asset for reuse.
- Lock the APP SHELL (e.g. left tree / center focus / right agent) and the canonical domain ontology. Write
  SITE.md (vision, principles from the critique, sitemap from FLOW.md, roadmap, project id, hosting).

## 5. GENERATE (Stitch baton loop) — see stitch-foundation.md
- One screen per generate call. designSystem reused. deviceType **DESKTOP** (uppercase; lowercase errors;
  omitting defaults to MOBILE). Prompt **<5000 chars** (long prompts cause component omission), plain
  language, the DESIGN-system block embedded, one coherent screen described region-by-region.
- ★ The screen's prompt opens with its FLOW.md purpose: which tasks this page serves, which elements it
  must expose, what each reacts with. Generating a page Stitch "thinks looks right" instead of the page
  the flow needs is how shells happen.
- Fetch htmlCode.downloadUrl → page.html; screenshot.downloadUrl + `=w<width>` → page.png. Persist screen
  ids/positions in metadata.json (get_project).

## 6. INTEGRATE (code — the value-add Stitch can't do)
- **Token-normalize**: replace Stitch's neon/near-brand hex with the DESIGN.md tokens (sed inline hex);
  verify body bg + no neon remains. Fix any sub-AA contrast.
- **Continuity**: unify stray names Stitch invented (it drifts study/project names per screen) to the ONE
  ontology across all screens.
- **Navigation = exactly FLOW.md's transition coverage list**: wire the real in-design affordances (tree nodes,
  breadcrumb, rows, brand) to sibling pages via a text-match injector (assets/design/integrate.py). Every
  edge in FLOW.md §5 gets wired; nothing ad-hoc. NO visible pill/tab screen-switcher (reviewers panned it).
- **Reactions & states**: elements whose FLOW row declares a reaction get it (target page, revealed panel,
  state change). Pages with declared empty/error states get those states reachable (even as a static
  variant), not just the happy path.
- **Real data canvases**: replace placeholder chart panels with real `<canvas>` renders appropriate to the
  domain (assets/design/charts.js: log-scale residuals w/ legend + convergence-target line; twin-axis time
  series w/ intervention marker; experimental-overlay w/ error bars; viridis field; grid-convergence). Locate
  panels by header text, append a fitted canvas, render. This single fix moves the craft/domain scores most.

## 7. AUDIT (deterministic detail gate — the machine catches it, not the eye) ★
- Serve locally, open each page in playwright-cli, inject `assets/design/audit.js`, evaluate
  `JSON.stringify(__ultraAudit())`. It returns per-page violations:
  - **clipped** — text cut by its box (button typeset short of pixels: scrollWidth/Height > client box) on visible
    interactive/label elements.
  - **fontDrift** — computed font families outside the DESIGN.md allowlist; distinct font-size count above
    the type-scale budget (pass the allowlist via `window.__DESIGN_TOKENS` before evaluating).
  - **deadCandidates** — interactive-looking elements with no wired destination/handler marker (a with
    empty/# href and no onclick/data-nav; button with no handler attribute outside a form).
  - **shell** — placeholder markers (lorem/TBD/Korean sample-data words…), unpainted canvases, near-zero unique content: the
    "meaningless page" signal, scored with reasons.
  - **overflowX / contrast** — page-level horizontal scroll; worst sub-AA text/bg pairs (solid-bg
    best-effort).
- **Gate: clipped 0 · deadCandidates 0 (or justified in FLOW.md) · fontDrift 0 · overflowX false ·
  shell pass · contrast AA** — then and only then RE-SCORE. Machine catches detail rot; models judge taste.

## 8. VERIFY (render + task walk — never claim blind)
- Serve locally (`python3 -m http.server`) and drive playwright-cli: confirm title, canvas count + painted
  dims, bg color = token, 0 neon. Full-page screenshot each hero screen and LOOK at it (Read the PNG) —
  confirm charts drew, no overlap, legible. file:// is blocked → serve over http.
  screenshot syntax: `screenshot --full-page --filename <path>` (positional arg = selector, not a path).
- ★ **FLOW task walk**: click through every edge in FLOW.md §5 — each task must be completable start→end
  by clicking only what a user sees. An unreachable step = a broken flow, same severity as a failed test.

## 9. RE-SCORE (GAN) + WALKTHROUGH (usage simulation)
- **Walkthrough first**: give the cold models FLOW.md's tasks (NOT the flow's answers) + the artifact, and
  have them *perform* each task as the persona — narrate where they click, what they expect to see, where
  they stall. A stall or "why is this button here?" is a ranked gap. This is usability testing with cold
  models; it catches placement, necessity, and reaction gaps that scoring alone misses.
- Then re-run the cold scoring panel on the UPDATED artifact, framing EXACTLY what changed (so they verify
  in source) but still asking for an independent /100 + remaining ranked blockers to the target.
- Optionally feed gemini the screenshots for a true VISUAL re-score (gemini takes images).

## 10. ITERATE
- Fix the top-ranked remaining gaps (flow breaks → continuity → real charts → domain depth → governance →
  shell consistency → de-noise hierarchy, roughly in impact order). Re-audit (§7 stays green), re-verify,
  re-score. Stop at target.

## 11. HANDOFF
- Publish final to traefik, Discord, accumulate. Output = approved **DESIGN.md + FLOW.md** + screen URLs.
  pm cites DESIGN.md as each screen card's design acceptance criterion AND FLOW.md's task flows as the
  card's E2E scenario seeds; loop follows both as the visual/UX SoT.

## Anti-patterns (learned the hard way)
- Designing screens before flows (pages with no owning task = shells by construction).
- A button that cannot answer "why is it needed / what appears when pressed" in one line each.
- Single-state design — no loading/empty/error variants anywhere.
- Leading the eval witness (bake-in conclusion → fake agreement).
- Calling a placeholder chart "done".
- 5000+ char Stitch prompts / deviceType "desktop" lowercase / forgetting designSystem reuse → drift.
- A visible top pill screen-switcher (reads as debug chrome; reviewers reject it).
- Cross-screen name/color drift (destroys expert trust).
- Self-hosting design mockups on claude.ai instead of the project's traefik tailnet.
