# Run the needlessly synchronous test files async

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 10)

## What to build

About 16 test files run synchronously even though they use no DDL and no global env. Together they cost about 4.4s per run. Make them `async: true`. Files that really must stay sync (`payments_test`, the error-tracker tests, `papra_handler_test`) get a one-line comment saying why.

## Acceptance criteria

- [ ] Every sync test file is either async or has a comment giving its reason
- [ ] The suite passes on at least three random seeds
- [ ] The synchronous part of the run is noticeably shorter

## Blocked by

None - can start immediately
