# No receipt for unpaid orders or unconfirmed course bookings

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (findings 6 and 7, gap 7)

## What to build

The order receipt must 404 unless the order is placed and paid. The course receipt must 404 unless the registration is confirmed. Today only the paid and confirmed cases are tested, so dropping either check passes the suite.

## Acceptance criteria

- [ ] `GET /order/:id/receipt` on an unpaid placed order returns 404
- [ ] The course receipt for a `:pending` registration returns 404
- [ ] Removing either match in the controllers makes a test fail

## Blocked by

None - can start immediately
