#!/usr/bin/env bats
# workflow_contract.bats — v0.16 invariants for the two fan-out workflow scripts. These scripts are
# single-file by contract (no imports; workflow-tool-spec.md §5), so the MANDATORY METHODOLOGY block is
# DUPLICATED across both — this suite is what keeps the two copies honest.
bats_require_minimum_version 1.5.0

setup() {
  WF="$BATS_TEST_DIRNAME/../workflows"
  LANE="$WF/lane-fanout.workflow.js"
  MS="$WF/milestone-fanout.workflow.js"
}

@test "workflow scripts are syntactically valid (AsyncFunction-wrapped; node --check cannot parse top-level return)" {
  command -v node >/dev/null || skip "node not installed"
  for f in "$WF"/*.workflow.js; do
    node -e '
      const fs = require("fs");
      const src = fs.readFileSync(process.argv[1], "utf8").replace(/^export\s+/gm, "");
      const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
      new AsyncFunction("args","agent","pipeline","parallel","phase","log","workflow","budget", src);
    ' "$f" || { echo "syntax error: $f"; return 1; }
  done
}

@test "METHODOLOGY block is byte-identical across both fan-out workflows" {
  a="$(sed -n '/ULTRALOOP:METHODOLOGY v1 BEGIN/,/ULTRALOOP:METHODOLOGY v1 END/p' "$LANE")"
  b="$(sed -n '/ULTRALOOP:METHODOLOGY v1 BEGIN/,/ULTRALOOP:METHODOLOGY v1 END/p' "$MS")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

@test "both LANE schemas require the methodology evidence object" {
  grep -Fq "required: ['status', 'summary', 'methodology']" "$LANE"
  grep -Fq "required: ['status', 'summary', 'methodology']" "$MS"
}

@test "both lane prompts inject METHODOLOGY and both verifiers inject METHODOLOGY_VERIFY" {
  grep -Fq '${METHODOLOGY}' "$LANE"
  grep -Fq '${METHODOLOGY_VERIFY}' "$LANE"
  grep -Fq '${METHODOLOGY}' "$MS"
  grep -Fq '${METHODOLOGY_VERIFY}' "$MS"
}
