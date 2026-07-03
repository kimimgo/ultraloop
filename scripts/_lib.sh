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
ue_scope_slug() {  # milestone title → filesystem-safe slug (for scoped markers)
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-|-$//g'
}
