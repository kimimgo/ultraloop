# community-refs — Stitch official docs, community, templates (always-ready references)

## Official
- Stitch docs — overview: https://stitch.withgoogle.com/docs/learn/overview/
- Stitch docs (root): https://stitch.withgoogle.com/docs/?pli=1
- Stitch home: https://stitch.withgoogle.com/home
- Stitch projects: https://stitch.withgoogle.com/projects/
- Stitch on X: https://x.com/stitchbygoogle

## Community / forum (Google AI Developers Forum)
- ★ Stitch Prompt Guide (the prompting bible): https://discuss.ai.google.dev/t/stitch-prompt-guide/83844
- Stitch topics (category): https://discuss.ai.google.dev/c/stitch/61
- labs.google subreddit: https://www.reddit.com/r/labsdotgoogle/

## Example projects (user kimimgo@gmail.com — for layout reference / forking)
3960381895381557263 · 13084246554538621772 · 3907361547178343444 · 13115250104160537282 ·
8329075419221652720 · 7843834577505286568 · 16242038197062096808 · 17168879426185116634 ·
7961213629411163965 · 2982813652353387172 · 7144321199231990450 · 10100603439629535839
> list via `npx … tool list_projects`; pull a screen's HTML via get_screen → htmlCode.downloadUrl.

## Prompt-rule cheat sheet (from the prompt guide — keep in working memory)
1. One screen + ≤2 changes per prompt. 2. <5000 chars, plain language (no XML/JSON). 3. Vibe adjectives set
the theme. 4. Say WHAT to change and HOW; reference elements by name. 5. Specify exact colors to keep theme
consistent. 6. Save a screenshot each step; rephrase if off. 7. DESKTOP (uppercase) for desktop; reuse the
designSystem asset across screens. 8. Stitch doesn't remember — be incremental and precise.

## Templates (this plugin — assets/design/)
- `DESIGN.md.template` — the design-system § block to embed in every baton prompt.
- `SITE.md.template` — vision · principles · sitemap · roadmap · project id · hosting.
- `next-prompt.md.template` — the baton (YAML frontmatter `page:` + the prompt body w/ DESIGN block).
- `integrate.py` — token normalization + text-match cross-nav injection across pages.
- `charts.js` — domain data canvases (log residuals + legend + tol line; twin-axis time series + intervention
  marker; experimental overlay + error bars; viridis field; grid-convergence/GCI).

## Verified scoring rubric (what cold reviewers reward, from the foamlab m11 run)
High scores require: set-based/iterative IA (not a wizard); transparency (raw config diff before run);
separated Verification vs Validation with uncertainty + sources; domain-correct instruments (log residuals,
real units, sim-time not %); cross-screen continuity; one coherent shell; real (not placeholder) data viz;
restrained visual hierarchy. Internal jargon, placeholder charts, name drift, and a pill switcher are the
recurring point-killers.
