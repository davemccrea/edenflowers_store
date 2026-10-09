# Replace CSS-class selectors with aria/data/visible-text checks

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 12)

## What to build

Assertions on `.line-through`, `.menu-disabled`, `.admin-badge-success` and `.admin-badge-error` break on a restyle. Assert on `aria-disabled`, a `data-status` attribute or visible text instead, adding the attribute to the markup where none exists.

## Acceptance criteria

- [ ] No test selects on a styling class
- [ ] Each replacement still fails if the behaviour it checks breaks

## Blocked by

None - can start immediately
