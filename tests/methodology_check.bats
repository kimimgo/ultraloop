#!/usr/bin/env bats
# methodology_check.bats — the v0.16 deterministic TDD-evidence gate (scripts/methodology_check.sh).
#   Commit ordering (a test:* commit before the feat:/fix:* commit it justifies) is the machine-checked
#   artifact of test-first work — a fabricated skillsInvoked list cannot forge the commit graph.
#   Real git fixtures in BATS_TMPDIR; no network, no gh.
bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/methodology_check.sh"
  FIX="$BATS_TMPDIR/ue_mc_${BATS_TEST_NUMBER}"
  rm -rf "$FIX"; mkdir -p "$FIX"
  git -C "$FIX" init -q -b main
  git -C "$FIX" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  unset ULTRALOOP_CONFIG
  cd "$FIX"   # methodology_check.sh reads the repo from cwd
}
teardown() { cd "$BATS_TEST_DIRNAME"; rm -rf "$FIX"; }

# helpers
c()  { printf '%s\n' "$2" >> "$FIX/$1"; git -C "$FIX" add "$1"; git -C "$FIX" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
br() { git -C "$FIX" checkout -q -b "$1" main; }

@test "test-first: test:* before feat:* → pass" {
  br feat/good
  c src.py "test: failing test for X"
  c src.py "feat: implement X"
  run bash "$SCRIPT" feat/good --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "test after feat → exit 5 (order violated)" {
  br feat/order
  c src.py "feat: implement first"
  c src.py "test: add test after"
  run bash "$SCRIPT" feat/order --base main
  [ "$status" -eq 5 ]
}

@test "implementation with no test at all → exit 5" {
  br feat/notest
  c src.py "feat: no test"
  run bash "$SCRIPT" feat/notest --base main
  [ "$status" -eq 5 ]
}

@test "prefix evasion: source change with no classified commits → exit 5" {
  br feat/evade
  c src.py "chore: sneak a feature in without a feat: prefix"
  run bash "$SCRIPT" feat/evade --base main
  [ "$status" -eq 5 ]
  [[ "$output" == *"evasion"* ]]
}

@test "docs-only change → not applicable, pass" {
  br docs/only
  c README.md "docs: update readme"
  c notes.md  "docs: more notes"
  run bash "$SCRIPT" docs/only --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs-only"* ]]
}

@test "scoped subjects test(x):/fix(x): are classified → pass" {
  br feat/scoped
  c src.py "test(core): failing case"
  c src.py "fix(core): make it pass"
  run bash "$SCRIPT" feat/scoped --base main
  [ "$status" -eq 0 ]
}

@test "warn mode → violation reported but exit 0" {
  printf 'methodology:\n  tdd_evidence: warn\n' > "$FIX/ul.yaml"
  export ULTRALOOP_CONFIG="$FIX/ul.yaml"
  br feat/warn
  c src.py "feat: impl first"
  c src.py "test: test after"
  run bash "$SCRIPT" feat/warn --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "off mode → pass regardless of order" {
  printf 'methodology:\n  tdd_evidence: off\n' > "$FIX/ul.yaml"
  export ULTRALOOP_CONFIG="$FIX/ul.yaml"
  br feat/off
  c src.py "feat: impl with no test"
  run bash "$SCRIPT" feat/off --base main
  [ "$status" -eq 0 ]
}

@test "empty branch (no commits ahead) → exit 5" {
  br feat/empty
  run bash "$SCRIPT" feat/empty --base main
  [ "$status" -eq 5 ]
}

@test "red/green cross-check: red is not a test:* commit / inverted ancestry → exit 6" {
  br feat/rg
  c src.py "test: red";  RED="$(git -C "$FIX" rev-parse HEAD)"
  c src.py "feat: green"; GREEN="$(git -C "$FIX" rev-parse HEAD)"
  # pass them INVERTED (red=the impl commit, green=the test commit)
  run bash "$SCRIPT" feat/rg --base main --red "$GREEN" --green "$RED"
  [ "$status" -eq 6 ]
}

@test "red/green cross-check: correct pair → pass" {
  br feat/rg2
  c src.py "test: red";  RED="$(git -C "$FIX" rev-parse HEAD)"
  c src.py "feat: green"; GREEN="$(git -C "$FIX" rev-parse HEAD)"
  run bash "$SCRIPT" feat/rg2 --base main --red "$RED" --green "$GREEN"
  [ "$status" -eq 0 ]
}

@test "base sync-merge commits are excluded (--no-merges) → pass" {
  br feat/merge
  c src.py "test: t"
  c src.py "feat: f"
  git -C "$FIX" checkout -q main
  printf x >> "$FIX/other.py"; git -C "$FIX" add other.py
  git -C "$FIX" -c user.name=t -c user.email=t@t commit -q -m "chore: main advance"
  git -C "$FIX" checkout -q feat/merge
  git -C "$FIX" -c user.name=t -c user.email=t@t merge -q --no-ff -m "merge: sync main" main
  run bash "$SCRIPT" feat/merge --base main
  [ "$status" -eq 0 ]
}
