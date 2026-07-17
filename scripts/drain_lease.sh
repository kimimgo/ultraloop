#!/usr/bin/env bash
# drain_lease.sh — single-active-drainer lease per SEAT (#3, lane seats since #5).
#   Seat = whole board (root ref, main worktree) or one workstream lane (child ref, lane worktree).
#   Different lanes drain in parallel; same seat stays single-drainer; root ⟂ lanes (hierarchy).
#
# Problem: N worktrees (or clones) can each start /ultraloop:loop against the SAME board and race
# over the same Ready cards. This script gives the board ONE drainer seat, atomically:
#   - with an `origin` remote → the lease lives at `refs/ultraloop/drain-lease` ON THE REMOTE.
#     Ref creation / fast-forward is server-side atomic (CAS): create fails if the ref appeared,
#     renew fast-forwards MY tip only — no check-then-set race. Board-scope: every clone sees it.
#   - without a remote → local ref with `git update-ref <new> <old>` CAS. Refs are stored in the
#     git COMMON dir, so all linked worktrees of the clone share the one seat.
# The lease record is an empty-tree commit whose message is a JSON line {holder,host,worktree,scope,ts};
# freshness = committer timestamp, TTL = config engine.goal.lease_ttl_minutes (default 45).
# It lives only under the hidden ref namespace — never reachable from branches, invisible in normal history.
#
# Subcommands (exit codes shared with roadmap_sync/stop-gate):
#   ensure   acquire if we hold no seat, renew if we do (the per-loop call — roadmap_sync gates on it)
#   acquire  take the seat (absent → create · stale → takeover · held fresh by another → exit 6)
#   renew    heartbeat: fast-forward my lease commit (lost seat → exit 6 — STOP draining)
#   release  give the seat back (idempotent; only deletes a lease we hold)
#   status   print holder info · exit 0=mine 1=absent 2=stale(other) 6=held(other,fresh) 5=unreachable
# exit 0 = seat held (drain allowed) · 6 = another drainer holds it (demote: read-only/wait, LOUD)
# exit 5 = transient (network/auth) · degraded grace: `ensure` keeps a recently-renewed seat through
#          a transient failure (< TTL since last successful renew) instead of flapping.
set -uo pipefail
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SDIR/_lib.sh" 2>/dev/null || { echo "lib missing" >&2; exit 5; }

# v0.15 (#5): lane seats — a lane worktree takes its OWN seat (refs/.../drain-lease/<lane>), so loops
# on DIFFERENT lanes drain in parallel (cards are partitioned by ws:<lane> labels — no race by
# construction). The root seat (whole-board drainer, main worktree) and lane seats mutually exclude
# each other (hierarchical): root acquire fails while any fresh lane seat exists, and vice versa.
ROOT_REF="refs/ultraloop/drain-lease"
LANE="$(ue_lane 2>/dev/null || true)"
REF="$ROOT_REF"; [ -n "$LANE" ] && REF="$ROOT_REF/$LANE"
REMOTE="${ULTRALOOP_LEASE_REMOTE:-origin}"
STATE_DIR="$(ue_state_dir)"
HOLDER_FILE="$STATE_DIR/drain-lease.holder"
TTL_MIN="$(cfg_get engine.goal.lease_ttl_minutes 45)"; case "$TTL_MIN" in ''|*[!0-9]*) TTL_MIN=45;; esac
NOW="$(date +%s)"
export GIT_TERMINAL_PROMPT=0

git rev-parse --git-dir >/dev/null 2>&1 || { ue_log "not a git repo — lease unavailable"; exit 5; }
have_remote() { git remote get-url "$REMOTE" >/dev/null 2>&1; }

holder_id() {  # stable per drainer seat (= per state dir); survives ticks/restarts of the same run
  local h; h="$(grep -E '^HOLDER=' "$HOLDER_FILE" 2>/dev/null | tail -1 | cut -d= -f2)"
  [ -n "$h" ] || h="$(hostname -s 2>/dev/null || echo host)-$NOW-$$"
  printf '%s' "$h"
}
save_holder() { { echo "HOLDER=$1"; echo "TIP=$2"; echo "RENEWED=$NOW"; } > "$HOLDER_FILE" 2>/dev/null || true; }

payload() {  # $1=holder $2=verb — one JSON line (machine record; hidden-ref only, never branch history)
  local wt scope
  wt="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  scope="$(ue_goal_scope 2>/dev/null || true)"
  printf '{"holder":"%s","host":"%s","worktree":"%s","lane":"%s","scope":"%s","%s":%s}' \
    "$1" "$(hostname 2>/dev/null || echo '?')" "$wt" "$LANE" "$scope" "$2" "$NOW"
}
mk_commit() {  # $1=msg [$2=parent] → sha
  local tree; tree="$(git hash-object -t tree /dev/null)"
  git -c user.name=lease -c user.email=lease@localhost commit-tree "$tree" ${2:+-p "$2"} -m "$1" 2>/dev/null
}

# lease_read → G_SHA/G_TS/G_MSG · rc 0=exists 1=absent 5=unreachable
lease_read() {
  G_SHA=""; G_TS=0; G_MSG=""
  if have_remote; then
    local line; line="$(timeout 20 git ls-remote "$REMOTE" "$REF" 2>/dev/null)" || return 5
    G_SHA="$(printf '%s' "$line" | awk '{print $1}')"
    [ -n "$G_SHA" ] || return 1
    if ! git cat-file -e "$G_SHA" 2>/dev/null; then
      timeout 30 git fetch --no-tags --quiet "$REMOTE" "$REF" 2>/dev/null || return 5
    fi
  else
    G_SHA="$(git rev-parse -q --verify "$REF" 2>/dev/null)" || return 1
    [ -n "$G_SHA" ] || return 1
  fi
  G_TS="$(git log -1 --format=%ct "$G_SHA" 2>/dev/null || echo 0)"
  G_MSG="$(git log -1 --format=%B "$G_SHA" 2>/dev/null || true)"
  return 0
}
lease_create() {  # $1=sha — atomic create (must not exist) · rc 0 ok
  if have_remote; then timeout 30 git push --quiet --no-verify "$REMOTE" "$1:$REF" >/dev/null 2>&1
  else git update-ref "$REF" "$1" "" 2>/dev/null; fi
}
lease_ff() {  # $1=new $2=old — atomic fast-forward/CAS · rc 0 ok
  if have_remote; then timeout 30 git push --quiet --no-verify "$REMOTE" "$1:$REF" >/dev/null 2>&1
  else git update-ref "$REF" "$1" "$2" 2>/dev/null; fi
}
lease_delete() {  # $1=old — best-effort delete (takeover/release)
  if have_remote; then timeout 30 git push --quiet --no-verify "$REMOTE" ":$REF" >/dev/null 2>&1
  else git update-ref -d "$REF" "$1" 2>/dev/null; fi
}
verify_mine() {  # after a write, confirm the ref really points at $1 (closes the takeover race window)
  local line sha
  if have_remote; then
    line="$(timeout 20 git ls-remote "$REMOTE" "$REF" 2>/dev/null)" || return 5
    sha="$(printf '%s' "$line" | awk '{print $1}')"
  else
    sha="$(git rev-parse -q --verify "$REF" 2>/dev/null)"
  fi
  [ "$sha" = "$1" ]
}

age_min() { printf '%s' $(( (NOW - ${G_TS:-0}) / 60 )); }
is_mine() { case "$G_MSG" in *"\"holder\":\"$1\""*) return 0;; *) return 1;; esac; }

# ── hierarchical exclusion (#5): root seat ⟂ every lane seat ─────────────────
conflicting_refs() {  # "sha refname" lines of seats that exclude MY seat · rc 5 = unreachable
  if [ -n "$LANE" ]; then
    # my seat is a lane → only the EXACT root ref excludes me (sibling lanes are legitimate parallel).
    # ⚠️ local mode must use an exact lookup — for-each-ref's prefix matching on "$ROOT_REF" would
    # also list sibling lane refs and wrongly block lane-parallel drains.
    if have_remote; then timeout 20 git ls-remote "$REMOTE" "$ROOT_REF" 2>/dev/null || return 5
    else
      local s; s="$(git rev-parse -q --verify "$ROOT_REF" 2>/dev/null || true)"
      [ -n "$s" ] && printf '%s %s\n' "$s" "$ROOT_REF"
      return 0
    fi
  else
    # my seat is the root (whole board) → every lane seat excludes me
    if have_remote; then timeout 20 git ls-remote "$REMOTE" "$ROOT_REF/*" 2>/dev/null || return 5
    else git for-each-ref --format='%(objectname) %(refname)' "$ROOT_REF/*" 2>/dev/null; fi
  fi
}
ref_ts() {  # $1=sha → committer epoch (fetches the object if needed) · empty on failure
  if ! git cat-file -e "$1" 2>/dev/null && have_remote; then
    timeout 30 git fetch --no-tags --quiet "$REMOTE" "$2" 2>/dev/null || true
  fi
  git log -1 --format=%ct "$1" 2>/dev/null || true
}
chk_conflicts() {  # rc 0=clear (stale conflicts reaped) · 6=fresh conflict (info printed) · 5=unreachable
  local lines sha ref ts
  lines="$(conflicting_refs)" || return 5
  [ -n "$lines" ] || return 0
  while IFS=$'\t ' read -r sha ref; do
    [ -n "$sha" ] || continue
    ts="$(ref_ts "$sha" "$ref")"
    if [ -n "$ts" ] && [ $(( (NOW - ts) / 60 )) -lt "$TTL_MIN" ] 2>/dev/null; then
      printf 'seat conflict: %s held fresh (%smin ago) · %s\n' "$ref" "$(( (NOW - ts) / 60 ))" "$(git log -1 --format=%B "$sha" 2>/dev/null | head -1)"
      return 6
    fi
    # stale (or unreadable) conflicting seat → reap best-effort so the hierarchy can't wedge on a dead drainer
    if have_remote; then timeout 30 git push --quiet --no-verify "$REMOTE" ":$ref" >/dev/null 2>&1 || true
    else git update-ref -d "$ref" "$sha" 2>/dev/null || true; fi
  done <<EOF
$lines
EOF
  return 0
}
post_create_yield() {  # $1=my sha — root↔lane simultaneous-create window: the OLDER seat wins, ties by sha
  local lines sha ref ts myts
  lines="$(conflicting_refs)" || return 0        # unreachable → keep seat (TTL bounds the risk)
  [ -n "$lines" ] || return 0
  myts="$(git log -1 --format=%ct "$1" 2>/dev/null || echo "$NOW")"
  while IFS=$'\t ' read -r sha ref; do
    [ -n "$sha" ] || continue
    ts="$(ref_ts "$sha" "$ref")"; [ -n "$ts" ] || continue
    [ $(( (NOW - ts) / 60 )) -lt "$TTL_MIN" ] 2>/dev/null || continue
    if [ "$ts" -lt "$myts" ] 2>/dev/null || { [ "$ts" -eq "$myts" ] 2>/dev/null && [ "$sha" \< "$1" ]; }; then
      lease_delete "$1" || true; rm -f "$HOLDER_FILE" 2>/dev/null || true
      printf 'seat conflict lost (older seat %s) — yielding\n' "$ref"
      return 6
    fi
  done <<EOF
$lines
EOF
  return 0
}
info_line() {  # holder info for the agent/human (stdout)
  printf 'lease %s · age %smin · ttl %smin · %s\n' "${1:-held}" "$(age_min)" "$TTL_MIN" "$(printf '%s' "$G_MSG" | head -1)"
}

do_acquire() {
  local H sha rc; H="$(holder_id)"
  lease_read; rc=$?
  case "$rc" in
    5) ue_log "lease read failed (network/auth?)"; return 5 ;;
    1)
      chk_conflicts; rc=$?; [ "$rc" -eq 0 ] || return "$rc"       # root⟂lane hierarchy (#5)
      sha="$(mk_commit "$(payload "$H" acquired)")" || return 5
      if lease_create "$sha" && verify_mine "$sha"; then
        post_create_yield "$sha" || return 6
        save_holder "$H" "$sha"; ue_log "drain lease acquired (seat: ${LANE:-board})"; return 0
      fi
      lease_read || true; info_line "lost create race"; return 6 ;;
    0)
      if is_mine "$H"; then do_renew_ff "$H"; return $?; fi
      if [ "$(age_min)" -ge "$TTL_MIN" ] 2>/dev/null; then
        ue_log "stale lease ($(age_min)min ≥ ${TTL_MIN}min) → takeover"
        chk_conflicts; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
        lease_delete "$G_SHA" || true
        sha="$(mk_commit "$(payload "$H" acquired)")" || return 5
        if lease_create "$sha" && verify_mine "$sha"; then
          post_create_yield "$sha" || return 6
          save_holder "$H" "$sha"; ue_log "drain lease taken over (seat: ${LANE:-board})"; return 0
        fi
        lease_read || true; info_line "lost takeover race"; return 6
      fi
      info_line "held by another drainer"; return 6 ;;
  esac
}

do_renew_ff() {  # $1=holder — assumes lease_read done and G_SHA is mine
  local sha
  sha="$(mk_commit "$(payload "$1" renewed)" "$G_SHA")" || return 5
  if lease_ff "$sha" "$G_SHA" && verify_mine "$sha"; then save_holder "$1" "$sha"; return 0; fi
  lease_read || true
  if [ -n "$G_SHA" ] && is_mine "$1"; then save_holder "$1" "$G_SHA"; return 0; fi   # concurrent self-renew
  info_line "lease lost"; return 6
}

do_renew() {
  local H rc; H="$(holder_id)"
  [ -f "$HOLDER_FILE" ] || { ue_log "no seat to renew — acquiring"; do_acquire; return $?; }
  lease_read; rc=$?
  case "$rc" in
    5) return 5 ;;
    1) ue_log "lease vanished — re-acquiring"; do_acquire; return $? ;;
    0) if is_mine "$H"; then do_renew_ff "$H"; return $?
       else info_line "lease lost to another drainer"; return 6; fi ;;
  esac
}

do_ensure() {
  local rc
  if [ -f "$HOLDER_FILE" ]; then do_renew; rc=$?; else do_acquire; rc=$?; fi
  if [ "$rc" = 5 ] && [ -f "$HOLDER_FILE" ]; then
    # degraded grace: a transient failure must not flap a healthy drainer; TTL still bounds the risk
    local last; last="$(grep -E '^RENEWED=' "$HOLDER_FILE" 2>/dev/null | tail -1 | cut -d= -f2)"; last="${last:-0}"
    if [ $(( (NOW - last) / 60 )) -lt "$TTL_MIN" ] 2>/dev/null; then
      ue_log "lease endpoint unreachable — holding seat on grace (last renew $(( (NOW - last) / 60 ))min ago)"; return 0
    fi
  fi
  return "$rc"
}

do_release() {
  local H; H="$(holder_id)"
  if lease_read && is_mine "$H"; then lease_delete "$G_SHA" || true; ue_log "drain lease released"; fi
  rm -f "$HOLDER_FILE" 2>/dev/null || true
  return 0
}

do_status() {
  local H rc; H="$(holder_id)"
  lease_read; rc=$?
  case "$rc" in
    5) echo "lease unreachable"; return 5 ;;
    1) echo "no lease"; return 1 ;;
  esac
  if is_mine "$H"; then info_line "held by THIS drainer"; return 0; fi
  if [ "$(age_min)" -ge "$TTL_MIN" ] 2>/dev/null; then info_line "stale (reclaimable)"; return 2; fi
  info_line "held by another drainer"; return 6
}

case "${1:-ensure}" in
  ensure)  do_ensure ;;
  acquire) do_acquire ;;
  renew)   do_renew ;;
  release) do_release ;;
  status)  do_status ;;
  *) echo "usage: drain_lease.sh [ensure|acquire|renew|release|status]" >&2; exit 2 ;;
esac
