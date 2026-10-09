# Replace CSS-class selectors with aria/data/visible-text checks

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 12)

## What to build

Assertions on `.line-through`, `.menu-disabled`, `.admin-badge-success` and `.admin-badge-error` break on a restyle. Assert on `aria-disabled`, a `data-status` attribute or visible text instead, adding the attribute to the markup where none exists.

## Acceptance criteria

- [ ] No test selects on a styling class
- [ ] Each replacement still fails if the behaviour it checks breaks

## Blocked by

None - can start immediately

## Comments

- The admin badge assertions match on visible text in their row or section (`[data-item-id]`, `#order-status`, `#order-fulfillment-summary`); the orders list ones in `orders_live_test.exs` were changed too.
- The unavailable menu items are matched by their existing `aria-disabled="true"`.
- The cancelled course bookings had nothing but the strikethrough to mark them, so their `<li>` now carries `data-status="cancelled"`.
- Each replaced assertion was checked to fail when its behaviour is broken.
