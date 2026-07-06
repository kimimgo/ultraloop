#!/usr/bin/env bash
# roadmap_readme.sh — the board README / short description (ProjectV2.readme|shortDescription).
#   The board is the SoT, so the project brief (linked repos, collaborators, special project rules) belongs ON the board:
#   humans see it in the GitHub UI, and a fresh session can mirror it locally to know the context immediately (BP#context).
#   ⚠️ Written in the product's working language — collaborators read it, so no tool/agent/automation names (messaging ghostwriter rule).
# usage:
#   roadmap_readme.sh get   [--pnode ID]                       # print the board README to stdout
#   roadmap_readme.sh set   [--file F | "<markdown>"] [--short "<desc>"] [--pnode ID]
#   roadmap_readme.sh cache [outfile] [--pnode ID]             # get → write a local mirror (default .claude/.ultraloop-context.md)
# exit 0=ok · 2=argument error · 3=board not configured · 5=API failure
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh"

CMD="${1:-}"; shift || true

# --pnode override (else config board.project_node_id) — lets the ultraloop side pass its own recorded node id.
PNODE=""; POS=(); SHORT=""; FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --pnode) PNODE="$2"; shift 2;;
  --short) SHORT="$2"; shift 2;;
  --file)  FILE="$2"; shift 2;;
  *) POS+=("$1"); shift;;
esac; done
[ -n "$PNODE" ] || PNODE="$(cfg_get board.project_node_id "")"
[ -n "$PNODE" ] || { ghr_log "board.project_node_id not set (probable cause: board not bootstrapped) — run roadmap_bootstrap.sh first, or pass --pnode"; exit 3; }

case "$CMD" in
get)
  gq -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { readme } } }' -f id="$PNODE" \
     --jq '.data.node.readme // ""' \
    || { ghr_log "readme read failed: $(head -1 /tmp/ghr_gq.err) (probable cause: token scopes/invalid node id)"; exit 5; } ;;

set)
  CONTENT=""
  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || { ghr_log "file not found: $FILE"; exit 2; }
    CONTENT="$(cat "$FILE")"
  elif [ "${#POS[@]}" -gt 0 ]; then
    CONTENT="${POS[0]}"
  fi
  [ -n "$CONTENT" ] || [ -n "$SHORT" ] || { echo "usage: roadmap_readme.sh set [--file F | \"<markdown>\"] [--short \"<desc>\"]"; exit 2; }
  ARGS=(-f query='mutation($p:ID!,$r:String,$s:String){ updateProjectV2(input:{projectId:$p,readme:$r,shortDescription:$s}){ projectV2{ id } } }' -f p="$PNODE")
  [ -n "$CONTENT" ] && ARGS+=(-f r="$CONTENT")
  [ -n "$SHORT" ]   && ARGS+=(-f s="$SHORT")
  gq "${ARGS[@]}" --jq '.data.updateProjectV2.projectV2.id | "✓ board README updated (\(.))"' \
    || { ghr_log "updateProjectV2 failed: $(head -1 /tmp/ghr_gq.err) (probable cause: token scopes or invalid board.project_node_id)"; exit 5; } ;;

cache)
  OUT="${POS[0]:-.claude/.ultraloop-context.md}"
  BODY="$("$SDIR/roadmap_readme.sh" get --pnode "$PNODE" 2>/dev/null)"
  [ -n "$BODY" ] || { ghr_log "board README is empty — nothing to mirror (set it first with: roadmap_readme.sh set --file <brief.md>)"; exit 0; }
  mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
  printf '%s\n' "$BODY" > "$OUT" && echo "✓ context mirror written: $OUT ($(wc -l <"$OUT" | tr -d ' ') lines)" \
    || { ghr_log "mirror write failed: $OUT"; exit 5; } ;;

*) echo "usage: roadmap_readme.sh get|set|cache  (see header)"; exit 2 ;;
esac
