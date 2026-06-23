# stitch-foundation — Google Stitch as the generation foundation

Google Stitch (labs.google, by David East / Google Labs) is the screen generator under `ultraloop:design`.
CLI/MCP: `@_davideast/stitch-mcp`. Remote API: `https://stitch.googleapis.com/mcp`. 14 tools incl.
create_project · generate_screen_from_text · edit_screens · list_screens · get_screen · get_project.

## Connecting (verified 2026-06-23, headless host)
1. `claude mcp list | grep stitch` — if `✔ Connected`, skip.
2. Else register stdio proxy + a durable API key (no expiry):
   `claude mcp add -s user stitch -e STITCH_API_KEY=<key> -- npx -y @_davideast/stitch-mcp proxy`
   Generate the key at labs.google.com/stitch settings. Key lives in the harness config only (not the repo).
3. First-time auth path (if no API key): `npx -y @_davideast/stitch-mcp init -c cc -t stdio` (client = `cc`,
   not `claude`). Headless → gcloud `--no-launch-browser` (paste-code). The wizard uses its OWN config dir
   `~/.stitch-mcp/config/` — credentials saved by a bare gcloud to `~/.config/gcloud/` must be copied there.
   Needs a GCP project with `stitch.googleapis.com` enabled (`gcloud services enable`).
4. ⚠️ HTTP transport (`-t http -H "X-Goog-Api-Key: …"`) connects but "tools fetch failed" → use the **stdio
   proxy** path. ⚠️ `proxy` needs `STITCH_API_KEY` or `STITCH_ACCESS_TOKEN` env (NOT plain OAuth).
> Full troubleshooting: project memory `stitch-mcp-setup`.

## Driving it (CLI, this session without a reconnect)
- Schema: `npx … tool <name> -s`. Invoke: `npx … tool <name> -d '<json>'` (or `-f payload.json`, `-o json`).
- create_project: `{"title":"…"}` → returns `projects/<id>`.
- generate_screen_from_text: `{"projectId":"<id>","deviceType":"DESKTOP","designSystem":"assets/<id>","prompt":"…"}`.
  Takes a few minutes; DO NOT retry on timeout — poll get_screen. Response:
  `outputComponents[].design.screens[0]` → `id`, `htmlCode.downloadUrl` (the HTML), `screenshot.downloadUrl`
  (append `=w<width>` for full-res), `theme` (namedColors/fonts), and a `designSystem` asset id (reuse it for
  every subsequent screen so they match).
- Output HTML = Tailwind (CDN) + Google Fonts + Material Symbols, dark-capable. External CDNs are fine for
  tailnet self-hosting (the user's browser fetches them).

## Prompt best-practices (Stitch official — forum prompt guide)
- **One screen, one or two changes per prompt.** Never bundle features. Stitch does not remember prior
  designs unless prompts are precise & incremental.
- **<5000 chars.** Long prompts cause Stitch to OMIT components. Plain language — NOT XML/JSON.
- **Vibe adjectives** drive color/font/imagery ("minimalist and focused"). **Be explicit about WHAT and HOW**
  ("add a search bar to the header", "2px solid border on inputs", "serif font"). Reference elements
  specifically. Specify the design-system colors to keep theme consistent.
- Save a screenshot after each successful step. Rephrase if a result is off; be more targeted.
- For ultraloop: embed the DESIGN.md § design-system block in every baton prompt, set deviceType DESKTOP,
  reuse the designSystem asset, describe the screen region-by-region (top bar / left / center / right), and
  keep ONE canonical domain narrative across all screens.

## Known reality
- Stitch produces strong LAYOUT/craft but: uses its own (often near-neon) accent + Inter-ish fonts → normalize
  in INTEGRATE; drifts study/project NAMES across screens → unify; renders charts as PLACEHOLDERS → inject
  real canvases. Stitch gets you ~80% craft fast; the remaining trust/domain/continuity work is the
  integrate+eval loop (`design-loop-protocol.md`).

## Templates & community
See `community-refs.md` for the official docs, prompt guide, forum, X, and example project URLs.
