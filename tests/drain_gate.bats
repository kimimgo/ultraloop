#!/usr/bin/env bats
# drain_gate.bats — the v0.14 drain gates (issues #2/#3/#4).
#   Real git fixtures (worktrees, a file:// "origin") in BATS_TMPDIR; gh is stubbed on PATH so the
#   suite is deterministic (no network). Each test isolates state via ULTRALOOP_STATE_DIR.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPTS="$BATS_TEST_DIRNAME/../scripts"
  FIX="$BATS_TMPDIR/ue_drain_${BATS_TEST_NUMBER}"
  rm -rf "$FIX"; mkdir -p "$FIX/bin" "$FIX/state-main" "$FIX/state-wt"

  # gh stub: authenticated; north-star query returns an empty body unless a fixture overrides UE_STUB_NS.
  cat >"$FIX/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")   exit 1 ;;
esac
if [ "$1" = "issue" ] && printf '%s\n' "$@" | grep -q "north-star"; then
  printf '%s' "${UE_STUB_NS:-}"; exit 0
fi
exit 0
STUB
  chmod +x "$FIX/bin/gh"
  PATH="$FIX/bin:$PATH"

  # main repo with a commit (worktrees need one)
  git -C "$FIX" init -q main-repo
  git -C "$FIX/main-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  cat >"$FIX/main-repo/ultraloop.config.yaml" <<'YAML'
repo: owner/app
engine:
  goal:
    scope: "board"
    lease_ttl_minutes: 45
YAML
  git -C "$FIX/main-repo" worktree add -q "$FIX/wt-a" -b wt-a
  cp "$FIX/main-repo/ultraloop.config.yaml" "$FIX/wt-a/ultraloop.config.yaml"

  export UE_STUB_NS=""
  unset ULTRALOOP_CONFIG ULTRALOOP_STATE_DIR
}

teardown() { rm -rf "$FIX"; }

# ── #4 worktree gate ─────────────────────────────────────────────────────────

@test "worktree_gate: main worktree → no gate (exit 0)" {
  cd "$FIX/main-repo"
  ULTRALOOP_STATE_DIR="$FIX/state-main" run bash "$SCRIPTS/worktree_gate.sh" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"main worktree"* ]]
}

@test "worktree_gate: linked worktree without token → exit 4 with context block" {
  cd "$FIX/wt-a"
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/worktree_gate.sh" check
  [ "$status" -eq 4 ]
  [[ "$output" == *"LINKED WORKTREE"* ]]
  [[ "$output" == *"scope"* ]]
}

@test "worktree_gate: confirm → check passes, and a NEWER run-start invalidates the token" {
  cd "$FIX/wt-a"
  export ULTRALOOP_STATE_DIR="$FIX/state-wt"
  run bash "$SCRIPTS/worktree_gate.sh" confirm
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS/worktree_gate.sh" check
  [ "$status" -eq 0 ]
  sleep 1; date +%s > "$FIX/state-wt/run-start"   # a new run starts after the confirmation
  run bash "$SCRIPTS/worktree_gate.sh" check
  [ "$status" -eq 4 ]
}

@test "worktree_gate: cost_guard --reset clears the confirm token (per-run confirmation)" {
  cd "$FIX/wt-a"
  export ULTRALOOP_STATE_DIR="$FIX/state-wt"
  bash "$SCRIPTS/worktree_gate.sh" confirm
  [ -f "$FIX/state-wt/worktree-drain-confirm" ]
  run bash "$SCRIPTS/cost_guard.sh" --reset
  [ "$status" -eq 0 ]
  [ ! -f "$FIX/state-wt/worktree-drain-confirm" ]
}

# ── #3 drain lease (no remote → local-ref CAS shared via the git common dir) ─

@test "drain_lease: acquire → second seat is refused (exit 6) → release frees it" {
  cd "$FIX/main-repo"
  ULTRALOOP_STATE_DIR="$FIX/state-main" run bash "$SCRIPTS/drain_lease.sh" acquire
  [ "$status" -eq 0 ]
  cd "$FIX/wt-a"   # sibling worktree = same clone, different seat
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/drain_lease.sh" ensure
  [ "$status" -eq 6 ]
  [[ "$output" == *"held by another"* ]]
  cd "$FIX/main-repo"
  ULTRALOOP_STATE_DIR="$FIX/state-main" run bash "$SCRIPTS/drain_lease.sh" release
  [ "$status" -eq 0 ]
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/drain_lease.sh" ensure
  [ "$status" -eq 0 ]
}

@test "drain_lease: renew keeps the seat; a stale lease (≥TTL) is taken over" {
  cd "$FIX/main-repo"
  export ULTRALOOP_STATE_DIR="$FIX/state-main"
  GIT_COMMITTER_DATE="2020-01-01T00:00:00" run bash "$SCRIPTS/drain_lease.sh" acquire
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS/drain_lease.sh" renew          # own seat renews fine even when old
  [ "$status" -eq 0 ]
  # forge a foreign STALE lease: point the ref at a ghost drainer's 2020 commit
  GHOST="$(GIT_COMMITTER_DATE="2020-01-01T00:00:00" git -C "$FIX/main-repo" -c user.name=x -c user.email=x@x \
    commit-tree "$(git -C "$FIX/main-repo" hash-object -t tree /dev/null)" -m '{"holder":"ghost"}')"
  git -C "$FIX/main-repo" update-ref refs/ultraloop/drain-lease "$GHOST"
  cd "$FIX/wt-a"
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/drain_lease.sh" ensure
  [ "$status" -eq 0 ]                                # stale (2020) → takeover succeeds
}

@test "drain_lease: works over a real remote (file:// origin) across clones" {
  git init -q --bare "$FIX/origin.git"
  git -C "$FIX/main-repo" remote add origin "$FIX/origin.git"
  git -C "$FIX/main-repo" push -q origin HEAD 2>/dev/null || true
  git clone -q "$FIX/origin.git" "$FIX/clone2"
  cp "$FIX/main-repo/ultraloop.config.yaml" "$FIX/clone2/ultraloop.config.yaml"
  cd "$FIX/main-repo"
  ULTRALOOP_STATE_DIR="$FIX/state-main" run bash "$SCRIPTS/drain_lease.sh" acquire
  [ "$status" -eq 0 ]
  cd "$FIX/clone2"
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/drain_lease.sh" ensure
  [ "$status" -eq 6 ]
}

# ── #2 scope resolution (board pointer > config, mismatch is loud) ───────────

@test "scope: board Active-Milestone wins and a config divergence returns rc 4" {
  cd "$FIX/main-repo"
  export ULTRALOOP_CONFIG="$FIX/main-repo/ultraloop.config.yaml"
  . "$SCRIPTS/_lib.sh"
  # board pointer only (config scope=board) → board value, rc 0
  export UE_STUB_NS='Goal text
Active-Milestone: M2 정합
more text'
  run ue_active_milestone
  [ "$status" -eq 0 ]
  [ "$output" = "M2 정합" ]
  # config points elsewhere → mismatch, rc 4, board value still printed
  cat >"$ULTRALOOP_CONFIG" <<'YAML'
repo: owner/app
engine:
  goal:
    scope: "milestone:M1 옛것"
YAML
  run --separate-stderr ue_active_milestone
  [ "$status" -eq 4 ]
  [ "$output" = "M2 정합" ]                          # board value still wins on stdout
  [[ "$stderr" == *"SCOPE MISMATCH"* ]]              # and the divergence is loud
  # board unreachable/absent → legacy config fallback, rc 0
  export UE_STUB_NS=""
  run ue_active_milestone
  [ "$status" -eq 0 ]
  [ "$output" = "M1 옛것" ]
}

# ── integration: roadmap_sync enforces the gates before any board read ───────

@test "roadmap_sync: linked worktree without confirmation → exit 4, no cards" {
  cd "$FIX/wt-a"
  export ULTRALOOP_CONFIG="$FIX/wt-a/ultraloop.config.yaml"
  ULTRALOOP_STATE_DIR="$FIX/state-wt" run bash "$SCRIPTS/roadmap_sync.sh"
  [ "$status" -eq 4 ]
  [[ "$output" == *"LINKED WORKTREE"* ]]
}

@test "roadmap_sync: lease held elsewhere → exit 6 (demoted, no cards)" {
  cd "$FIX/main-repo"
  ULTRALOOP_STATE_DIR="$FIX/state-wt" bash "$SCRIPTS/drain_lease.sh" acquire   # another seat takes it
  export ULTRALOOP_CONFIG="$FIX/main-repo/ultraloop.config.yaml"
  ULTRALOOP_STATE_DIR="$FIX/state-main" run bash "$SCRIPTS/roadmap_sync.sh"
  [ "$status" -eq 6 ]
  [[ "$output" == *"held by another"* ]]
}
