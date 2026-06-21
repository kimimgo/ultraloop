# TypeScript 룰

`_base.md`와 함께 적용. 아래는 기본값 — 프로젝트 관례가 있으면 그쪽을 존중한다.

## 도구

- **lint**: `eslint`
- **type**: `tsc --noEmit` (tsconfig `strict: true`)
- **test**: `vitest` 또는 `jest`
- **패키지**: `pnpm` 우선

## 레이아웃

```
package.json
tsconfig.json          # "strict": true
src/...
tests/  (또는 *.test.ts 코로케이션 — 프로젝트 관례 따름)
```

## package.json scripts (권장)

```jsonc
{
  "scripts": {
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run --coverage",
    "build": "tsc -p tsconfig.build.json"  // 또는 vite/tsup 등
  }
}
```

## 명령 예시

```bash
pnpm install
pnpm lint
pnpm typecheck
pnpm test          # 커버리지 목표: coverage_target (기본 80)
pnpm build
```

## 규약

- `strict: true` 유지. `any` 남발 금지 — 불가피하면 주석으로 사유.
- 신규 기능은 테스트 먼저(TDD). 커버리지 임계는 vitest/jest 설정에 `coverage_target`으로.
- lock 파일(`pnpm-lock.yaml`) 커밋. 빌드 산출물(`dist/`)은 `.gitignore`.
