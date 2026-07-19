# Branches & worktrees — parallel lanes + hardened GC (worktree-strategy)

## 0. baseRef — the lane branching base (fixed at bootstrap)
Parallel lanes run with `isolation:"worktree"`, each in its own worktree (separate directory + separate branch).
What decides "from which point a new branch is cut" for this isolation is the Claude Code native `worktree.baseRef`
setting, and `bootstrap_repo.sh` (§6.5) records it in the target repo's `.claude/settings.json` (`config.worktree.base_ref`).

| Value | Branching base | Effect |
|---|---|---|
| **`fresh`** (default·recommended) | `origin/<default>` | Every lane starts from a clean remote base → reproducible. Local unpushed commits do **not** enter the lanes |
| `head` | local `HEAD` | Only when lanes must be built on top of in-progress unpushed commits |

- The scope of application is the same in 3 places: `claude --worktree`, the `EnterWorktree` tool, and **agent/Workflow `isolation:"worktree"`** (= parallel lanes).
- ultraloop recommendation = **`fresh`**: lanes do not inherit each other's half-done work, which reduces parallel merge conflicts and nondeterminism.
  Use `head` only in the exceptional situation where work must run on top of an unpushed local base.

## 1. Principles
- trunk-based + short-lived branches (1:1 with issues), delete the branch after squash merge, protect `main`.
- Parallelism = per-lane **git worktree** separation (`config.worktree.root`, default `../.ue-worktrees/<issue#>-<slug>`),
  each lane 1 (sub)agent.

## 2. Non-conflicting lane grouping
The orchestrator groups into concurrent lanes **only**:
- No `Depends-on` violation (predecessor cards are Done).
- **Non-overlapping module directories** (lanes do not touch the same files/directories at the same time → minimize merge conflicts).
- If a conflict is possible, serialize (one lane at a time).
Concurrent lane cap = `config.worktree.max_lanes` (default 2).

## 3. Commands (`worktree_mgr.sh`)
```bash
worktree_mgr.sh create <issue#> <slug>   # create the lane worktree + check out the branch
worktree_mgr.sh list                      # current worktrees + card-state mapping
worktree_mgr.sh gc                         # clean up only finished lanes (rules below)
```

## 4. ★ Hardened GC — in-flight protection (REQ-WT-4)
GC at loop start (①). **Removal target = the card is in a terminal state (Done/Closed) and the branch is merged into main.**

**Exclusions (preserve) — checked in two layers:**

| # | Preservation rule | Who checks |
|---|---|---|
| 1 | worktree with uncommitted changes | `gc`, deterministic (exit 10) |
| 2 | **unmerged** branch ahead of main | `gc`, deterministic (exit 11) |
| 3 | **non-terminal card** (Ready/In-Progress/In-Review/E2E/**Parked**) | the **orchestrator** filters before calling gc |
| 4 | item **waiting in the approval queue** (`ultraloop-approvals/*.pending` references the issue#) | `gc`, best-effort preserve |

- Rules ①② are checked by `gc` **deterministically** at the git level, without a token.
- Rule ③ needs a board query (project-scope token); running it per worktree would be heavy and fragile. Instead, **the orchestrator
  hands gc only the lanes confirmed Done on the board it has already read** (the loop sees the board at ①②, so the context is
  there). gc never looks at the board itself.
- Rule ④: `gc` greps the approval-queue pending files for the issue# and preserves **best-effort** (if enqueue did not put the
  issue# into the action it can miss, but even then rule ② (ahead>0) blocks most cases).

→ When in doubt, **preserve** (careful). Prevents the race where GC deletes in-flight parallel work.

## 5. Removal is high risk
Worktree removal (especially uncommitted/unmerged) is §14 high risk → block and confirm (approval queue). `worktree_mgr.sh gc`
ends with **exit 2 (preserved)** when preservation rules apply, and with **exit 0 (nothing-to-do)** when there was nothing to
delete in the first place (it never force-deletes).

## 6. Native worktree environment — orca + ows (baseline assumption, not a runtime dependency)
The baseline environment is orca + git-worktrees, but this is **advisory** — no script requires it.

- **Transient per-card TDD lanes stay raw git — UNCHANGED.** `worktree_mgr.sh create` cuts `../.ue-worktrees/<issue>-<slug>`
  and the Workflow tool's `isolation:"worktree"` handles per-lane isolation (§0·§3 above). Nothing here changes.
- **Long-lived workstream lanes** are spawned with the platform-native tools:
  - `ows wt-spawn <project> <slug> [--kick "<prompt>"]` — creates `.worktrees/<slug>` + branch `wt/<slug>` + a tmux session; OR
  - `orca-ide worktree create --repo id:<repoId> --name <task> --agent claude --prompt "..." --json`.
  - Removal: `ows wt-rm <project> <slug>` or `orca-ide worktree rm --worktree id:<repoId>::<path>`.
- This is where `superpowers:using-git-worktrees`' "platform-native tools preferred" seam resolves.
- **CRITICAL: no script requires orca/ows.** Availability is only a `·` advisory line in the config doctor; CI/bats pass
  without it. The transient TDD lanes above never touch orca/ows.
