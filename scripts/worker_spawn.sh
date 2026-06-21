#!/usr/bin/env bash
# worker_spawn.sh — N레포 워커(tmux cc 세션) 기동·지시·관찰 (multi-repo-orchestration.md §4·§6)
#   spawn 권한은 메타 단독 — 워커/훅이 이 스크립트를 호출하면 안 된다(재귀 spawn 금지).
# usage:
#   worker_spawn.sh list                      # config repos + 세션 생존 여부
#   worker_spawn.sh spawn [--all|<name>] [--dry-run]   # 캡·스태거·worktree 격리 포함 기동
#   worker_spawn.sh inject <name> <task_file>          # send-keys 1줄 + capture-pane 수신확인 + 재시도
#   worker_spawn.sh capture <name> [lines]             # 워커 화면 관찰
# exit 0=ok · 2=설정/인자 부족 · 4=동시성 캡 도달 · 6=주입 실패(수신확인 불가)
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || true

SOCK="$(cfg_get orchestration.tmux_socket "")"
SPAWN="$(cfg_get orchestration.spawn tmux_new_session)"
CHANNEL="$(cfg_get orchestration.channel auto)"
# 메시지 브로커(선택): 워커에 지시를 영속 전달. 비면 send-keys 폴백.
HUB="${ULTRALOOP_BROKER_URL:-$(cfg_get orchestration.broker_url '')}"
# 외부 세션 매니저 CLI(선택): 세션명 = 레포 basename(접두사 없음 → 그 CLI로 attach 호환).
#   비면 plain tmux. CC 기동은 여기서 한다(세션 매니저가 CC를 안 띄워도 동작).
SESSMGR="$(cfg_get orchestration.session_mgr_cmd '')"
SM_MODE=0; case "$SPAWN" in session_mgr) [ -n "$SESSMGR" ] && command -v "$SESSMGR" >/dev/null 2>&1 && SM_MODE=1;; esac
TMUX_CMD=(tmux); [ "$SM_MODE" = 0 ] && [ -n "$SOCK" ] && TMUX_CMD=(tmux -L "$SOCK")
PERM="$(cfg_get orchestration.permission_mode bypassPermissions)"
MAXW="$(cfg_get orchestration.max_concurrent_workers 2)"
STAG="$(cfg_get orchestration.stagger_seconds 20)"
REPOS_JSON="$(cfg_get repos "[]")"
hub_ok() { curl -s -m 2 "$HUB/health" 2>/dev/null | grep -q '"status":"ok"'; }

repo_field() { # repo_field <name> <key> [default]
  printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
n,k,d=sys.argv[1],sys.argv[2],sys.argv[3] if len(sys.argv)>3 else ""
for r in json.load(sys.stdin):
    if r.get("name")==n or r.get("name","").split("/")[-1]==n: print(r.get(k,d)); break
else: print(d)' "$1" "$2" "${3:-}"
}
repo_names() { printf '%s' "$REPOS_JSON" | python3 -c 'import json,sys
for r in json.load(sys.stdin): print(r["name"])'; }
sess_of() { [ "$SM_MODE" = 1 ] && basename "$1" || echo "ul-$(basename "$1")"; }
alive() { "${TMUX_CMD[@]}" has-session -t "$1" 2>/dev/null; }
live_count() { local n=0; while read -r R; do alive "$(sess_of "$R")" && n=$((n+1)); done < <(repo_names); echo "$n"; }

cmd="${1:-list}"; shift || true
case "$cmd" in
list)
  echo "workers (socket=${SOCK:-default}, cap=$MAXW):"
  repo_names | while read -r R; do
    S="$(sess_of "$R")"; alive "$S" && st="● live" || st="○ down"
    echo "  $st  $S  ($R  path=$(repo_field "$R" path '?'))"
  done ;;

spawn)
  TARGET="${1:-}"; DRY=0; [ "$TARGET" = "--dry-run" ] && { DRY=1; TARGET="--all"; }
  [ "${2:-}" = "--dry-run" ] && DRY=1
  [ -n "$TARGET" ] || TARGET="--all"
  repo_names | while read -r R; do
    [ "$TARGET" != "--all" ] && [ "$R" != "$TARGET" ] && [ "$(basename "$R")" != "$TARGET" ] && continue
    S="$(sess_of "$R")"; P="$(repo_field "$R" path "")"
    P="${P/#\~/$HOME}"
    alive "$S" && { echo "  ✓ $S 이미 live(멱등)"; continue; }
    [ -n "$P" ] && [ -d "$P" ] || { echo "  ✗ $R path 미설정/부재($P) — config repos[].path 필요"; continue; }
    if [ "$(live_count)" -ge "$MAXW" ]; then echo "  ✗ 동시성 캡($MAXW) 도달 — $R 보류(사용량·tmux 부하 가드)"; exit 4; fi
    # 호스트 점유 충돌 → worktree 격리 (isolation:worktree 명시 또는 호스트 cwd가 레포 안)
    WANT_ISO="$(repo_field "$R" isolation "")"
    case "$PWD/" in "$P"/*) WANT_ISO=worktree;; esac
    if [ "$WANT_ISO" = "worktree" ]; then
      WT="$(dirname "$P")/$(basename "$P")-ul-worker"
      if [ ! -d "$WT" ]; then
        BR="ul/$(basename "$P")-worker"; DEFB="$(cfg_get default_branch main)"
        [ "$DRY" = 1 ] && echo "DRY: git -C $P worktree add $WT -b $BR $DEFB" || \
          git -C "$P" worktree add "$WT" -b "$BR" "$DEFB" 2>/dev/null || \
          git -C "$P" worktree add "$WT" "$BR" 2>/dev/null || { echo "  ✗ $R worktree 격리 실패"; continue; }
      fi
      P="$WT"; echo "  · $R 호스트 점유 → worktree 격리: $P"
    fi
    if [ "$DRY" = 1 ]; then echo "DRY: ${TMUX_CMD[*]} new-session -d -s $S -c $P  claude --permission-mode $PERM"; continue; fi
    "${TMUX_CMD[@]}" new-session -d -s "$S" -c "$P" "claude --permission-mode $PERM" \
      && echo "  ✓ spawned $S (cwd=$P)" || { echo "  ✗ $S 기동 실패"; continue; }
    # 외부 세션 매니저가 별도 영속 명령을 주지 않아도 된다 — 영속은 tmux 세션 자체로.
    # 새 worktree/clone의 CC는 '폴더 신뢰' 다이얼로그에 멈춘다(bypassPermissions로도 못 넘음 — 전주기
    # E2E 실측). 방금 우리가 만든 디렉토리라 자동 신뢰가 안전. TUI 준비(상태바)까지 이 단계에서 보장.
    for _t in 1 2 3 4 5 6; do
      sleep 5
      PANE="$("${TMUX_CMD[@]}" capture-pane -t "$S" -p 2>/dev/null)"
      printf '%s' "$PANE" | grep -q "trust this folder" \
        && { "${TMUX_CMD[@]}" send-keys -t "$S" Enter; echo "  · 폴더 신뢰 자동 확인"; }
      printf '%s' "$PANE" | grep -q "shift+tab" && { echo "  · TUI 준비 완료"; break; }
    done
    ue_log "stagger ${STAG}s (동시 기동 금지 — 사용량 스파이크/서버 부하 가드)"; sleep "$STAG"
  done ;;

inject)
  NAME="${1:-}"; FILE="${2:-}"
  [ -n "$NAME" ] && [ -f "$FILE" ] || { echo "usage: inject <name> <task_file>"; exit 2; }
  S="$(sess_of "$NAME")"; alive "$S" || { echo "✗ $S 세션 없음 — 먼저 spawn"; exit 2; }
  MSG="$FILE 파일을 읽고 그 지시를 그대로 수행하라."   # 멀티라인 직접 주입 금지(부록 B)
  # 채널 1순위 = 메시지 브로커(내구성 메시징: inbox에 영속, 워커가 SessionStart/폴로 수신).
  #   전달 성공 후 send-keys는 '깨우기' 보너스(실패해도 메시지는 inbox에 남는다 — 유실 없음).
  #   브로커가 설정(ULTRALOOP_BROKER_URL/orchestration.broker_url)돼 있고 도달 가능할 때만 사용.
  if [ -n "$HUB" ] && [ "$CHANNEL" != "send_keys" ] && hub_ok; then
    BODY="$(python3 -c 'import json,sys; print(json.dumps({"from":sys.argv[1],"to":sys.argv[2],"body":sys.argv[3]}))' "ultraloop-meta" "$S" "$MSG")"
    if curl -fsS -m 3 -X POST "$HUB/team/messages" -H 'content-type: application/json' -d "$BODY" >/dev/null 2>&1; then
      "${TMUX_CMD[@]}" send-keys -t "$S" "메시지 브로커 inbox(GET $HUB/team/inbox/$S?consume=true)에서 받은 지시를 수행하라." Enter 2>/dev/null || true
      echo "✓ injected → $S (broker durable + nudge)"; exit 0
    fi
    ue_log "broker send 실패 → send_keys 폴백"
  fi
  for try in 1 2 3; do
    "${TMUX_CMD[@]}" send-keys -t "$S" "$MSG" Enter; sleep 3
    "${TMUX_CMD[@]}" capture-pane -t "$S" -p 2>/dev/null | grep -qF "$FILE" \
      && { echo "✓ injected → $S (send-keys 수신확인 try=$try)"; exit 0; }
    ue_log "수신 미확인(try=$try) — 재시도"
  done
  echo "✗ $S 주입 수신확인 실패(3회) — capture로 상태 확인 후 수동 개입"; exit 6 ;;

capture)
  NAME="${1:-}"; [ -n "$NAME" ] || { echo "usage: capture <name> [lines]"; exit 2; }
  "${TMUX_CMD[@]}" capture-pane -t "$(sess_of "$NAME")" -p 2>/dev/null | tail -n "${2:-30}" ;;

*) echo "usage: worker_spawn.sh list|spawn|inject|capture"; exit 2 ;;
esac
