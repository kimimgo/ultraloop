# README contract

The README is the document that gets **a newcomer (or a fresh agent) to their first success as fast as possible**.
Do not make things up — write only commands/env/features that actually work.

## Required sections

1. **Overview** — 1~3 sentences on what this project is and what it does.
2. **Requirements** — runtime/tool versions (e.g. Docker, Python 3.12, Node 20). Only what exists.
3. **Single-command install & run** ← the core
4. **Configuration (env)** — the list of required environment variables and their meaning. Secrets by name only, without values (see `.env.example`).
5. **Tests** — the command to run tests, how to check coverage.
6. **E2E startup** — how to run E2E. State which single command `up` calls.

## Why the "single-command startup" is the core

The `up` stage of the E2E runner (`e2e.runner`) **calls exactly the command written in the README**.

- README:

  ```
  ## Install & run
  docker compose up -d
  ```

- E2E `up`: runs `docker compose up -d`, **exactly the same** as above.

Therefore the README's startup command and the actual startup procedure must **always match**.
If they diverge, that itself is a defect — this is the contract that blocks "documentation hallucination"
(it is in the README but does not actually work).

Conditions of a good single command:
- One line brings up the whole stack (app + dependent services, db, etc.).
- After startup, a health check can confirm it is "up".
- If preparation (build/migrations etc.) is needed, it is either included inside that command or stated as the single line right before it.

## Writing tone

- Commands as copy-pasteable code blocks.
- Vague wording like "usually" or "probably" is forbidden — only what has been verified.
- Screenshots/diagrams are optional. Command accuracy comes first.
