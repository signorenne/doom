# {{PROJECT}} agent guide

The rules to keep in memory before changing this repo. Prettier and
ESLint enforce most of them; when this file and the tooling disagree,
the tooling wins and both get fixed.

## Hard rules

- TypeScript, `strict`. No `any` that a type could name; `unknown` and a
  narrowing check where the shape is genuinely unknown.
- No default exports except where a framework demands one, so a name
  cannot drift between the file and its importers.
- Components stay small enough to read at once; logic that is not about
  the view lives in `src/lib/` and is unit tested.
- Tailwind classes in the markup, not `@apply` in a stylesheet: the
  class list is the styling, in one place.
- Every fetch has its failure handled where it is called; no promise
  left unawaited.

## Before you finish

- `yarn lint`, `yarn check`, `yarn test`.
- No `console.log` left behind, no commented-out code.
