# TypeScript rules

Applied together with `_base.md`. Below are defaults — when the project has its own conventions, respect those.

## Tools

- **lint**: `eslint`
- **type**: `tsc --noEmit` (tsconfig `strict: true`)
- **test**: `vitest` or `jest`
- **packaging**: `pnpm` first

## Layout

```
package.json
tsconfig.json          # "strict": true
src/...
tests/  (or *.test.ts colocation — follow project convention)
```

## package.json scripts (recommended)

```jsonc
{
  "scripts": {
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run --coverage",
    "build": "tsc -p tsconfig.build.json"  // or vite/tsup etc.
  }
}
```

## Command examples

```bash
pnpm install
pnpm lint
pnpm typecheck
pnpm test          # coverage target: coverage_target (default 80)
pnpm build
```

## Contract

- Keep `strict: true`. No scattering `any` — when unavoidable, justify it with a comment.
- New features start with tests (TDD). Set the coverage threshold as `coverage_target` in the vitest/jest config.
- Commit the lock file (`pnpm-lock.yaml`). Build output (`dist/`) goes in `.gitignore`.
