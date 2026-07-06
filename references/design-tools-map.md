# design-tools-map — verified harness design/UX tools to orchestrate (call, don't reimplement)

`ultraloop:design` is an ORCHESTRATOR. These tools are installed and verified in the harness. Pick by phase.
Availability check: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/design_env_check.sh`.

## Foundation & generation (Stitch core)
| Tool | Use for |
|---|---|
| **Stitch MCP** (`stitch:` tools; CLI `npx -y @_davideast/stitch-mcp`) | create_project · generate_screen_from_text · edit_screens · list/get_screen · get_project. The screen generator. See `stitch-foundation.md`. |
| **stitch-utilities:taste-design** | Generate DESIGN.md (anti-slop premium tokens) — run FIRST to set the system. |
| **stitch-utilities:enhance-prompt** | Turn a vague screen idea into a strong Stitch prompt. |
| **stitch-utilities:design-md** / **stitch-design:extract-design-md** | Extract a DESIGN.md from existing screens/code. |
| **stitch-design:generate-design / manage-design-system / code-to-design** | Stitch MCP design ops (screens, design systems, code→design). |
| **stitch-build:shadcn-ui / react-components / react-native** | Convert approved Stitch designs → production components (hand to loop). |

## Craft / anti-slop (hand-build & polish)
| Tool | Use for |
|---|---|
| **artifact-design** | Self-contained production-grade HTML artifact: brainstorm tokens→critique→commit palette→build. The right skill for a single self-hosted mockup file. |
| **taste-skill** ★ | Anti-slop frontend (landing/portfolio/redesign), audit-first, no-template. **Call at FOUNDATION (anti-slop DIRECTION) + CRITIQUE (audit-first on existing mockups).** |
| **impeccable** ★ | UI improvement: hierarchy, IA, cognitive load, a11y, motion, microcopy, theming. **Call at INTEGRATE (polish the integrated screens) + ITERATE (drive the top-gap fixes).** |
| **frontend-design** (plugin) | Distinctive production frontend; avoids generic AI aesthetic. |

## Evaluation (the GAN scoring loop — the differentiator)
| Tool | Use for |
|---|---|
| **codex CLI** (`codex exec --sandbox read-only`, model gpt-5.5 xhigh) | Cold critique / domain lens / re-score. |
| **gemini CLI** (`gemini -m gemini-3.1-pro-preview -p`) | Cold critique / holistic; CAN take screenshots for visual eval. |
| **tri-model-review** | Claude Opus + Gemini 3.1 Pro + Codex in parallel on one prompt → consensus/disagreement/synthesis. |
| **gemini-image-eval** (project skill) | Vision-based quality eval of rendered screenshots / output images. |
> Always COLD (no leading), FULL artifact attached, MULTIPLE angles. Convergence = signal.

## Review gates
| Tool | Use for |
|---|---|
| **gstack-design-review** | Designer's-eye QA: spacing/hierarchy/slop/slow-interactions → fixes. |
| **gstack-design-consultation** | Research landscape → propose a complete design system + previews. |
| **gstack-design-shotgun** | Generate N variants → comparison board → structured feedback. |
| **gstack-plan-design-review** | Designer's-eye review of a plan (pre-build). |

## Verify & host
| Tool | Use for |
|---|---|
| **playwright-cli** | Headless render-verify: open(http) → eval (canvas/nav/contrast) → `screenshot --full-page --filename`. file:// blocked → serve over http first. |
| **artifacts (traefik)** | Self-host mockups on tailnet: `infra/services/artifacts/publish.sh --discord <file>` → URL to Discord; `clear.sh` to recall. Accumulate; don't claude.ai. |

## Diagrams / IA
| Tool | Use for |
|---|---|
| **diagram-render / gstack-diagram** | User-flow, sitemap, IA, state-machine diagrams (PNG/SVG, headless). |

## Decision guide
- New product, no design yet → taste-design (system) → Stitch generate → integrate → eval loop.
- Existing design to fix → cold multi-model CRITIQUE first → then foundation/regenerate the weak screens.
- Need production components → after design approved, stitch-build:shadcn-ui / react-components (loop's job).
- Pure single artifact (no Stitch) → artifact-design + taste-skill, still run the eval loop.
