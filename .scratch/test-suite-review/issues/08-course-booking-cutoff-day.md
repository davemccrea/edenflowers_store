# Course booking is open on register_before and closed the day after

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 8, gap 10)

## What to build

Test the booking cutoff at its boundary, using the Helsinki today. The current tests only use `today - 2`.

## Acceptance criteria

- [ ] `register_before: today` is accepted
- [ ] `register_before: today - 1` is refused
- [ ] Moving the cutoff by one day in `ReserveSeats` makes a test fail

## Blocked by

None - can start immediately

## Comments

Replaced the `today - 2` cutoff test with "booking is open on register_before itself and closed the day after", using `HelsinkiToday.today()`.
Confirmed caught both ways: closing a day late (`Date.before?(register_before, today - 1)`) and a day early (`not Date.after?(register_before, today)`).
