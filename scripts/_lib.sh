#!/usr/bin/env bash
# _lib.sh — shared helper for ultraloop scripts. Use via `source`.
#   cfg_get <dotted.key> [default]   : read a value from ultraloop.config.yaml (python3+yaml, grep fallback)
#   skill_dir                         : absolute path of this skill directory
#   state_dir                         : directory for queue/heartbeat/state files (creation guaranteed)
#   log <msg>                         : timestamped log (stderr)
# Intentionally thin — deterministic behavior only; everything else is judged by the caller (the agent).

ue_skill_dir() {
  # Plugin runtime uses CLAUDE_PLUGIN_ROOT, standalone skill uses CLAUDE_SKILL_DIR. If neither, derive from script location.
  local s="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:-}}"
  if [ -z "$s" ]; then
    # _lib.sh lives inside scripts/, so the parent is the plugin/skill root
    s="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  printf '%s' "$s"
}

ue_config_path() {
  # Explicit env takes priority
  if [ -n "${ULTRALOOP_CONFIG:-}" ]; then printf '%s' "$ULTRALOOP_CONFIG"; return; fi
  # Walk upward from cwd to the root — so even when the Stop hook runs with a subdirectory cwd
  # it still finds the repo-root ultraloop.config.yaml (prevents the cfg_get default-fallback bug when unfound).
  local d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/ultraloop.config.yaml" ] && { printf '%s' "$d/ultraloop.config.yaml"; return; }
    d="$(dirname "$d")"
  done
  # Fallback: the project root that Claude Code provides
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/ultraloop.config.yaml" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR/ultraloop.config.yaml"; return
  fi
  printf '%s' "./ultraloop.config.yaml"
}

ue_state_dir() {
  # Explicit env override takes priority (used as-is).
  local base="${ULTRALOOP_STATE_DIR:-}"
  if [ -n "$base" ]; then
    mkdir -p "$base" 2>/dev/null || true
    printf '%s' "$base"; return
  fi
  # Default = isolate per repo in a subdirectory. loop-count/run-start/heartbeat/goal state/lock used to be
  # shared across all loops (/tmp/ultraloop), so concurrent loops overwrote each other counters/locks — this prevents that collision.
  local root key
  root="$(dirname "$(ue_config_path)")"
  case "$root" in /*) ;; *) root="$(cd "$root" 2>/dev/null && pwd || printf '%s' "$PWD")";; esac
  key="$(basename "$root")"
  key="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$key" ] && [ "$key" != "_" ] && [ "$key" != "." ] || key="repo-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
  local d="${TMPDIR:-/tmp}/ultraloop/$key"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
}

# cfg_get a.b.c [default] — read a dotted-notation key from config.
cfg_get() {
  local key="$1" def="${2:-}" cfg
  cfg="$(ue_config_path)"
  [ -f "$cfg" ] || { printf '%s' "$def"; return 0; }
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" "$key" "$def" <<'PY' 2>/dev/null || printf '%s' "$def"
import sys
cfg, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    import yaml
    with open(cfg) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print(default); sys.exit(0)
cur = data
for part in key.split('.'):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(default); sys.exit(0)
if cur is None:
    print(default)
elif isinstance(cur, bool):
    print('true' if cur else 'false')
elif isinstance(cur, (list, dict)):
    import json; print(json.dumps(cur, ensure_ascii=False))
else:
    print(cur)
PY
  else
    # Fallback: rough match on the last key segment only (nesting unsupported). Default if absent.
    local last="${key##*.}"
    grep -E "^\s*${last}\s*:" "$cfg" 2>/dev/null | head -1 | sed -E 's/^[^:]*:\s*//; s/\s*$//; s/^["'\'']//; s/["'\'']$//' | grep . || printf '%s' "$def"
  fi
}

ue_log() { printf '[ultraloop %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# resolve repo owner/name (config.repo or current gh repo)
ue_repo() {
  local r; r="$(cfg_get repo "")"
  if [ -n "$r" ]; then printf '%s' "$r"; return 0; fi
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true
}

# v0.10: run scope — engine.goal.scope: "board" (default, full-board completion) or
# "milestone:<title>" (the run ends when that milestone is drained). Machine-level
# counterpart of north-star.md §2 milestone goals: per-run goals become gate-enforceable.
ue_goal_scope() {  # prints the milestone title, or "" for board scope
  local s; s="$(cfg_get engine.goal.scope board)"
  case "$s" in milestone:*) printf '%s' "${s#milestone:}";; *) : ;; esac
}

# v0.14 (#2): the active-milestone POINTER's SoT is the board, not the branch-committed config.
# pm records one `Active-Milestone: <title>` line in the north-star issue body (single writer);
# every worktree/branch resolves the same pointer from there, so a worktree fork or a main reset
# cannot silently retarget the run. config engine.goal.scope stays as legacy fallback + cache.
ue_scope_board() {  # prints the board-side Active-Milestone title. rc 0=found · 1=absent · 2=query failed
  # v0.15 (#5): lane-aware — a lane resolves ITS OWN north-star issue (north-star + ws:<lane> labels).
  # The whole-board resolver only applies when the repo has exactly ONE north star (single-workstream
  # legacy); with per-workstream stars a repo-wide singular pointer is undefined → absent (config fallback).
  local repo="${1:-$(ue_repo)}" body lane
  [ -n "$repo" ] || return 2
  command -v gh >/dev/null 2>&1 || return 2
  lane="$(ue_lane)"
  if [ -n "$lane" ]; then
    body="$(gh issue list -R "$repo" --label north-star --label "ws:$lane" --state open --limit 1 --json body -q '.[0].body' 2>/dev/null)" || return 2
  else
    local cnt; cnt="$(gh issue list -R "$repo" --label north-star --state open --limit 20 --json number -q 'length' 2>/dev/null)" || return 2
    [ "$cnt" = "1" ] || return 1
    body="$(gh issue list -R "$repo" --label north-star --state open --limit 1 --json body -q '.[0].body' 2>/dev/null)" || return 2
  fi
  [ -n "$body" ] || return 1
  # LC_ALL=C: milestone titles are often non-ASCII (Korean) — locale-aware sed can refuse to match
  # them (observed on ko_KR.UTF-8); byte-wise matching is encoding-proof for this machine marker.
  printf '%s\n' "$body" | LC_ALL=C sed -nE 's/^[[:space:]]*Active-Milestone:[[:space:]]*(.+)$/\1/p' | head -1 | LC_ALL=C sed -E 's/[[:space:]]+$//' | grep . || return 1
}

# ue_active_milestone — resolve the effective run scope with board precedence + divergence detection.
#   stdout: milestone title ("" = board scope)
#   rc 0 = resolved · 4 = MISMATCH (board pointer and config scope disagree — caller must fail LOUD, not drain)
#   Board unreachable → degrade to the config value (pre-#2 behavior) with a stderr warning.
ue_active_milestone() {
  local cfg board rc
  cfg="$(ue_goal_scope 2>/dev/null || true)"
  board="$(ue_scope_board 2>/dev/null)"; rc=$?
  case "$rc" in
    0)
      if [ -n "$cfg" ] && [ "$cfg" != "$board" ]; then
        ue_log "SCOPE MISMATCH: board Active-Milestone=\"$board\" vs config goal.scope=\"$cfg\" — board is SoT; reconcile via pm"
        printf '%s' "$board"; return 4
      fi
      printf '%s' "$board"; return 0 ;;
    1) printf '%s' "$cfg"; return 0 ;;   # no board pointer → legacy config-only path
    *) [ -n "$cfg" ] && ue_log "board scope query failed → degraded to config goal.scope=\"$cfg\""
       printf '%s' "$cfg"; return 0 ;;
  esac
}

# v0.14 (#4): linked-worktree detection. In the main worktree git-dir == common-dir (.git);
# in a linked worktree git-dir is <common>/worktrees/<name>. rc 0 = linked worktree.
ue_is_linked_worktree() {
  local gd cd
  gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  cd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$cd" in /*) ;; *) cd="$(cd "$cd" 2>/dev/null && pwd)" || return 1 ;; esac
  [ -n "$gd" ] && [ -n "$cd" ] && [ "$gd" != "$cd" ]
}

# v0.15 (#5): workstream lane — PARTITION over lock. A linked worktree IS a lane; the lane name
# derives from the worktree directory basename (.worktrees/chat → "chat"), zero-config — pm uses
# the same name in card labels (ws:<lane>). Main worktree = "" = whole-board drainer.
ue_lane() {
  ue_is_linked_worktree || { printf ''; return 0; }
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf ''; return 0; }
  basename "$top" | tr -cd 'A-Za-z0-9._-'
}
ue_scope_slug() {  # milestone title → filesystem-safe slug (for scoped markers)
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-|-$//g'
}

# v0.16 (#6): superpowers plugin probe — the build-methodology carrier. Prints the superpowers
# plugin root (the dir that holds skills/); rc 1 if absent. Pure filesystem — no gh, no orca, no
# network — so the doctor/bootstrap barrier and the bats suite stay deterministic. The load-bearing
# key file is skills/test-driven-development/SKILL.md (the methodology's core skill).
ue_superpowers_dir() {
  local cand hit p
  # 1) explicit override — tests/CI and non-standard installs
  cand="${ULTRALOOP_SUPERPOWERS_DIR:-}"
  if [ -n "$cand" ] && [ -f "$cand/skills/test-driven-development/SKILL.md" ]; then
    printf '%s' "$cand"; return 0
  fi
  # 2) live dev copy of the plugin (mirrors the gh-roadmap local-copy convention)
  if [ -f "$HOME/.claude/skills/superpowers/skills/test-driven-development/SKILL.md" ]; then
    printf '%s' "$HOME/.claude/skills/superpowers"; return 0
  fi
  # 3) installed layouts — plugins/cache/<marketplace>/superpowers/<hash>/… is the real one on this host.
  #    compgen -G expands each pattern safely (empty on no-match, no nullglob/nomatch surprises).
  for p in \
    "$HOME/.claude/plugins/cache/*/superpowers/*/skills/test-driven-development/SKILL.md" \
    "$HOME/.claude/plugins/*/superpowers/skills/test-driven-development/SKILL.md" \
    "$HOME/.claude/plugins/marketplaces/*/superpowers*/skills/test-driven-development/SKILL.md"; do
    hit="$(compgen -G "$p" 2>/dev/null | head -1)"
    [ -n "$hit" ] && { printf '%s' "${hit%/skills/test-driven-development/SKILL.md}"; return 0; }
  done
  return 1
}
