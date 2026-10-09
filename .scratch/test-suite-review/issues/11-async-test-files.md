# Run the needlessly synchronous test files async

Status: resolved

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

## Comments

- Made 17 test files `async: true`, including `papra_handler_test`: its Oban jobs live in the per-test sandbox, so it had no real reason to stay sync.
- Four files stay sync, each with a one-line reason: `payments_test` and `stripe_handler_retry_test` (ALTER TABLE), and the two error-tracker tests (`Application.put_env`).
- The suite passes on seeds 1, 4242, 98765 and 31337. The sync part of the run went from 5.2s to about 1.5s.
