# Card planning — loop plans and builds each card on its own (card-planning)

The **per-card planning gate** (v0.13 M2). Before the first failing test (Red), `loop` turns ONE board card
into a self-contained, testable implementation plan — then designs, then builds. This is what lets loop take
a single card and drive it end to end without pm pre-decomposing tactics.

> Discipline cherry-picked from superpowers `writing-plans` (obra/superpowers, MIT), adapted to ultraloop's
> card/issue/E2E model. ultraloop changes: the plan lives **on the card** (not a `plans/` file); the design
> is a bundled `imgyu-techdoc` HTML; no superpowers sub-skill dispatch (ultraloop fans out via
> `lane-fanout`/`milestone-fanout`, `workflow-tool-spec.md`). This is a `loop` tool, not `pm`.

## Per-card flow (loop, unattended)

One Ready card →
1. **Design** — author a single self-contained HTML design doc via the bundled **`imgyu-techdoc`** skill; publish it via **`artifacts-ops`** → put the URL in the card's `Design-Doc` field.
2. **Plan** — write the card's implementation plan (below) into the issue *before Red*.
3. **Build** — TDD (Red→Green→Refactor) task by task, atomic commits, rulepack gates (`tdd-layer.md`).
4. **Evidence** — pre-merge production E2E, dual-recorded (`e2e-production.md`, `card-container.md`).

## Writing the plan (before Red)

Assume a fresh lane agent with zero context for this codebase and questionable taste. Document everything it needs.

- **File structure first.** List which files are created/modified and each one's single responsibility. Files that change together live together; split by responsibility, not by layer. This locks in decomposition before tasks.
- **Task right-sizing.** A task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. Fold setup/config/scaffolding/docs into the task whose deliverable needs them; split only where a reviewer could reject one task while approving its neighbor. Each task ends with an independently testable deliverable.
- **Bite-sized steps** (one action, 2–5 min): write the failing test → run it, see it fail → minimal code to pass → run, see it pass → commit.
- **Interfaces block per task** — *Consumes* (exact signatures used from earlier tasks) / *Produces* (exact names, param/return types later tasks rely on). A lane sees only its own task; this is how it learns neighbors' names.
- **No placeholders.** These are plan failures — never write them: "TBD / TODO / implement later", "add appropriate error handling / validation / handle edge cases", "write tests for the above" without the test code, "similar to Task N" (repeat it — tasks may be read out of order), any reference to a type/function not defined in some task. Every code step shows the code; every command shows expected output.

## Where the plan lives

On the card. Write the plan into the issue body under `## Implementation plan` (or a top comment) before the first Red commit — this is the card=container discipline (`card-container.md`): plan → design link → progress → evidence all on one card. Not a separate file.

## Self-review (loop runs this on itself, inline — not a subagent)

1. **Acceptance coverage** — every acceptance criterion on the card maps to a task. List any gap; add the task.
2. **Placeholder scan** — search the plan for the red-flag patterns above; fix inline.
3. **Type consistency** — names/signatures used in later tasks match what earlier tasks defined (`clearLayers()` in Task 3 vs `clearFullLayers()` in Task 7 is a bug).

Fix inline and move on — no re-review pass.

## Envelope

The plan stays inside the card's milestone envelope (`north-star.md §4.5`). If planning reveals the work crosses a milestone boundary or conflicts with an anti-goal, stop and escalate to pm — do not widen scope in the plan.
