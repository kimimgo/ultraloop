#!/usr/bin/env bash
# ultraloop:design environment check (idempotent). Reports tool availability; never hard-fails.
set -u
ok(){ printf "  ✔ %s\n" "$1"; }
no(){ printf "  x %s\n" "$1"; }
echo "== ultraloop:design env =="

# Stitch MCP
if claude mcp list 2>/dev/null | grep -qiE "stitch.*Connected"; then ok "Stitch MCP: connected"
elif command -v npx >/dev/null 2>&1; then no "Stitch MCP: not connected (see references/stitch-foundation.md — needs STITCH_API_KEY proxy)"
else no "Stitch MCP: npx missing"; fi

# Eval models
command -v codex >/dev/null 2>&1 && ok "codex CLI ($(codex --version 2>/dev/null | head -1))" || no "codex CLI missing (cold eval)"
command -v gemini >/dev/null 2>&1 && ok "gemini CLI ($(gemini --version 2>/dev/null | head -1))" || no "gemini CLI missing (cold eval)"

# Render verify
command -v playwright-cli >/dev/null 2>&1 && ok "playwright-cli (render verify)" || no "playwright-cli missing (render verify)"

# Hosting
[ -x /home/imgyu/workspace/infra/services/artifacts/publish.sh ] && ok "artifacts publish.sh (traefik self-host)" || no "artifacts publish.sh not found (host may differ)"

# Design skills (best-effort presence)
for s in taste-design artifact-design impeccable taste-skill frontend-design tri-model-review gemini-image-eval; do
  found=0; for pth in ~/.claude*/skills/$s ~/.claude/plugins/cache/*/*/*/skills/$s; do [ -e "$pth" ] && { found=1; break; }; done
  if [ "$found" = 1 ]; then ok "skill: $s"; else no "skill: $s (optional)"; fi
done
echo "== done =="
