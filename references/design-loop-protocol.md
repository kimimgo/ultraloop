# design-loop-protocol — the verified UI/UX GAN loop

The body of `ultraloop:design`. A generate→evaluate→fix→re-score loop driven to a numeric target.
Empirically validated 2026-06-23 (foamlab m11): a "color-copied" mockup scored 5/100 by the user and
35–58 by cold domain reviewers was rebuilt with this loop to codex 84 / gemini 92 in one generate+integrate
pass, then iterated upward by closing the ranked gaps.

## 1. SCOPE
- Understand the product, the real end-user, and the DOMAIN workflow (not an imagined one). Recover the
  true data model / task loops from source or prior art if they exist. Fix constraints: brand, stack,
  hosting (self-host traefik tailnet), accessibility (WCAG AA), device (DESKTOP first unless told).
- Output: a one-paragraph product truth + the canonical domain narrative (names/entities reused on EVERY
  screen — drift here is the #1 trust-killer reviewers flag).

## 2. CRITIQUE (cold, multi-model, NO leading) — only if a prior design exists
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

## 3. FOUNDATION
- Establish ONE design system: run taste-design → DESIGN.md (anti-slop tokens: surfaces, one cool + one warm
  accent <80% sat, status colors with icon+label, type scale weight-driven, spacing scale, 2 radii, no neon
  glow). Pin fonts (avoid Inter for premium). Create/normalize a Stitch designSystem asset for reuse.
- Lock the APP SHELL (e.g. left tree / center focus / right agent) and the canonical domain ontology. Write
  SITE.md (vision, principles from the critique, sitemap, roadmap, project id, hosting).

## 4. GENERATE (Stitch baton loop) — see stitch-foundation.md
- One screen per generate call. designSystem reused. deviceType **DESKTOP** (uppercase; lowercase errors;
  omitting defaults to MOBILE). Prompt **<5000 chars** (long prompts cause component omission), plain
  language, the DESIGN-system block embedded, one coherent screen described region-by-region.
- Fetch htmlCode.downloadUrl → page.html; screenshot.downloadUrl + `=w<width>` → page.png. Persist screen
  ids/positions in metadata.json (get_project).

## 5. INTEGRATE (code — the value-add Stitch can't do)
- **Token-normalize**: replace Stitch's neon/near-brand hex with the DESIGN.md tokens (sed inline hex);
  verify body bg + no neon remains. Fix any sub-AA contrast.
- **Continuity**: unify stray names Stitch invented (it drifts study/project names per screen) to the ONE
  ontology across all screens.
- **Navigation**: wire the real in-design affordances (tree nodes, breadcrumb, rows, brand) to sibling pages
  via a text-match injector (assets/design/integrate.py). NO visible pill/tab screen-switcher (reviewers
  panned it). Verify clicks navigate.
- **Real data canvases**: replace placeholder chart panels with real `<canvas>` renders appropriate to the
  domain (assets/design/charts.js: log-scale residuals w/ legend + convergence-target line; twin-axis time
  series w/ intervention marker; experimental-overlay w/ error bars; viridis field; grid-convergence). Locate
  panels by header text, append a fitted canvas, render. This single fix moves the craft/domain scores most.

## 6. VERIFY (render — never claim blind)
- Serve locally (`python3 -m http.server`) and drive playwright-cli: confirm title, canvas count + painted
  dims, nav click changes location, bg color = token, 0 neon. Full-page screenshot each hero screen and LOOK
  at it (Read the PNG) — confirm charts drew, no overlap, legible. file:// is blocked → serve over http.
  screenshot syntax: `screenshot --full-page --filename <path>` (positional arg = selector, not a path).

## 7. RE-SCORE (GAN)
- Re-run the cold panel on the UPDATED artifact, framing EXACTLY what changed (so they verify in source) but
  still asking for an independent /100 + remaining ranked blockers to the target.
- Optionally feed gemini the screenshots for a true VISUAL re-score (gemini takes images).

## 8. ITERATE
- Fix the top-ranked remaining gaps (continuity → real charts → domain depth → governance → shell
  consistency → de-noise hierarchy, roughly in impact order). Re-verify, re-score. Stop at target.

## 9. HANDOFF
- Publish final to traefik, Discord, accumulate. Output = approved DESIGN.md + screen URLs. pm cites the
  DESIGN.md as each screen card's design acceptance criterion; loop follows DESIGN.md as the visual SoT.

## Anti-patterns (learned the hard way)
- Leading the eval witness (bake-in conclusion → fake agreement).
- Calling a placeholder chart "done".
- 5000+ char Stitch prompts / deviceType "desktop" lowercase / forgetting designSystem reuse → drift.
- A visible top pill screen-switcher (reads as debug chrome; reviewers reject it).
- Cross-screen name/color drift (destroys expert trust).
- Self-hosting design mockups on claude.ai instead of the project's traefik tailnet.
