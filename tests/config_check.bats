#!/usr/bin/env bats
# config_check.bats — the v0.13 "config doctor" (scripts/config_check.sh).
#   Each test builds a self-contained fixture in BATS_TMPDIR and perturbs exactly one
#   REQUIRED input so the failure reason is unambiguous. gh is stubbed on PATH so the
#   suite is deterministic (no network, no ambient auth). gh-roadmap is the bundled
#   plugin skill, so the REQUIRED sub-skill check passes from the repo tree itself.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/config_check.sh"
  FIX="$BATS_TMPDIR/ue_fix_${BATS_TEST_NUMBER}"
  rm -rf "$FIX"; mkdir -p "$FIX/.claude" "$FIX/bin"

  # Deterministic gh stub: authenticated, no ambient repo, runner query returns a count.
  cat >"$FIX/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")   exit 1 ;;   # no ambient repo → ue_repo falls back to empty
esac
[ "$1" = "api" ] && { echo 1; exit 0; }
exit 0
STUB
  chmod +x "$FIX/bin/gh"
  PATH="$FIX/bin:$PATH"

  # A fully valid config + completed-bootstrap marker (the OK baseline).
  cat >"$FIX/ultraloop.config.yaml" <<'YAML'
repo: owner/app
roadmap:
  token_env: UE_PROJECT_TOKEN
YAML
  : >"$FIX/.claude/.ultraloop-bootstrapped"

  export ULTRALOOP_CONFIG="$FIX/ultraloop.config.yaml"
  export UE_PROJECT_TOKEN="dummy-token"
  unset GH_TOKEN
}

teardown() { rm -rf "$FIX"; }

@test "missing ultraloop.config.yaml → non-zero exit with a clear reason" {
  export ULTRALOOP_CONFIG="$FIX/does-not-exist.yaml"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ultraloop.config.yaml"* ]]
}

@test "missing required repo → fail" {
  cat >"$FIX/ultraloop.config.yaml" <<'YAML'
repo: ""
roadmap:
  token_env: UE_PROJECT_TOKEN
YAML
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo"* ]]
}

@test "no token env AND no 'project' scope on gh's own token → fail with both remedies" {
  unset UE_PROJECT_TOKEN
  run bash "$SCRIPT"                                  # stub `gh auth status` prints no scopes
  [ "$status" -ne 0 ]
  [[ "$output" == *"token"* ]]
  [[ "$output" == *"gh auth refresh"* ]]
}

@test "no token env but gh keyring token has the 'project' scope → ok (capability, not mechanism)" {
  unset UE_PROJECT_TOKEN
  cat >"$FIX/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") echo "  - Token scopes: 'gist', 'project', 'repo'"; exit 0 ;;
  "repo view")   exit 1 ;;
esac
[ "$1" = "api" ] && { echo 1; exit 0; }
exit 0
STUB
  chmod +x "$FIX/bin/gh"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"keyring"* ]]
}

@test "ok config → exit 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}
