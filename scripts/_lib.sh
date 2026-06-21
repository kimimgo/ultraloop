#!/usr/bin/env bash
# _lib.sh — ultraloop 스크립트 공유 헬퍼. `source` 해서 쓴다.
#   cfg_get <dotted.key> [default]   : ultraloop.config.yaml 값 읽기 (python3+yaml, 폴백 grep)
#   skill_dir                         : 이 스킬 디렉토리 절대경로
#   state_dir                         : 큐/하트비트/상태 파일 디렉토리(생성 보장)
#   log <msg>                         : 타임스탬프 로그(stderr)
# 의도적으로 얇게 — 결정적 동작만, 나머지는 호출자(에이전트)가 판단.

ue_skill_dir() {
  # 플러그인 런타임은 CLAUDE_PLUGIN_ROOT, 단독 스킬은 CLAUDE_SKILL_DIR. 둘 다 없으면 스크립트 위치로 도출.
  local s="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:-}}"
  if [ -z "$s" ]; then
    # _lib.sh 는 scripts/ 안에 있으므로 부모가 플러그인/스킬 루트
    s="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  printf '%s' "$s"
}

ue_config_path() {
  # 명시 env 우선
  if [ -n "${ULTRALOOP_CONFIG:-}" ]; then printf '%s' "$ULTRALOOP_CONFIG"; return; fi
  # cwd부터 루트까지 거슬러 올라가며 탐색 — Stop 훅이 서브디렉토리 cwd에서 실행돼도
  # repo 루트의 ultraloop.config.yaml 을 찾는다(미발견 시 cfg_get default 폴백 버그 방지).
  local d="$PWD"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/ultraloop.config.yaml" ] && { printf '%s' "$d/ultraloop.config.yaml"; return; }
    d="$(dirname "$d")"
  done
  # 폴백: Claude Code가 주는 프로젝트 루트
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/ultraloop.config.yaml" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR/ultraloop.config.yaml"; return
  fi
  printf '%s' "./ultraloop.config.yaml"
}

ue_state_dir() {
  # 명시 env override 우선(그대로 사용).
  local base="${ULTRALOOP_STATE_DIR:-}"
  if [ -n "$base" ]; then
    mkdir -p "$base" 2>/dev/null || true
    printf '%s' "$base"; return
  fi
  # 기본 = 레포별 서브디렉토리로 격리. loop-count·run-start·heartbeat·goal state·lock 이
  # 전 루프 공유(/tmp/ultraloop)였어 동시 루프가 서로의 카운트/락을 덮어쓰던 충돌을 막는다.
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

# cfg_get a.b.c [default] — config에서 점 표기 키를 읽는다.
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
    # 폴백: 1단계 키만 대충(중첩은 미지원). 없으면 default.
    local last="${key##*.}"
    grep -E "^\s*${last}\s*:" "$cfg" 2>/dev/null | head -1 | sed -E 's/^[^:]*:\s*//; s/\s*$//; s/^["'\'']//; s/["'\'']$//' | grep . || printf '%s' "$def"
  fi
}

ue_log() { printf '[ultraloop %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# repo owner/name 해석 (config.repo 또는 gh 현재 레포)
ue_repo() {
  local r; r="$(cfg_get repo "")"
  if [ -n "$r" ]; then printf '%s' "$r"; return 0; fi
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true
}
