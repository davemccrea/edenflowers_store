# Tests use the Helsinki date

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (findings 9 and 13)

## What to build

The date picker tests take the expected month from `Date.utc_today()`, but the component uses Helsinki time, so they fail between 21:00 and 24:00 UTC on the last day of a month. Some tests also hard-code dates that will soon be in the past (`2026-11-03` in the subscriptions LiveView test, `2026-12-25` and `2026-12-26` in the fulfillment calendar reset test).

## Acceptance criteria

- [ ] The date picker tests take the expected month from the Helsinki today
- [ ] The hard-coded future dates are replaced with dates relative to the Helsinki today
- [ ] The suite still passes

## Blocked by

None - can start immediately
