# Undo a skip, and make the account actions safe and reachable

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items A6, A8, A11, A13 and A15 in `10-ux-audit.md`.

Decision: add an `:unskip` action. Keep a single skipped date; longer absences use pause.

## Acceptance criteria

- [x] **A6.** `Subscription` `:unskip` removes the next date from `skipped_dates`. Same policy and cutoff as `:skip`; admin bypasses the cutoff. Account page shows "Deliver on … after all" when the next date is skipped, plus the hint "Away for longer? Pause instead."
- [x] **A8.** Cancel uses an in-app dialog instead of `data-confirm`: "Stop your subscription? No more deliveries or charges. Want a break instead? Pause it." Buttons "Stop subscription" and "Keep it". Focus moves into the dialog and returns on close.
- [x] **A11.** Skip, Pause, Resume, Cancel and Update card are at least 44px tall.
- [x] **A13.** Save is disabled until size or frequency changes. The confirmation names the date it applies from and the new price: "From 6 November: Small, every 4 weeks, €45 per delivery." Size options show their price.
- [x] **A15.** Focus doesn't drop to `<body>` after Pause or Resume.
- [x] Strings translated (sv, fi). Tests for `:unskip` (domain + policy + cutoff) and the account page.

## Blocked by

- `12-account-status.md` (same template; avoids conflicts)

## Comments

**Built (slice 13)**

- `Subscription` `:unskip` removes the next date from `skipped_dates`, with the same state check, cutoff and policies as `:skip`; Jennie bypasses the cutoff. Interface `Orders.unskip_subscription`. Domain tests cover it, including the policy and cutoff.
- The account page offers "Deliver on … after all" and "Away for longer? Pause instead." Skip no longer asks for confirmation, since it can now be undone.
- Cancel opens an in-app `<dialog class="modal">` (opened through the existing `drawer:open` event): "Stop your subscription? There will be no more deliveries or charges. Want a break instead? Pause it." with **Keep it** (autofocus) and **Stop subscription**. The native dialog handles focus trapping and return.
- Save is disabled until size or frequency differs (`edit_subscription` phx-change). The confirmation names the date it applies from and the new price, and size options show prices.
- Pause and Resume share one id, so the button is patched in place and keeps focus.
- 44px targets: buttons are `.btn` md size; text links carry `min-h-11`.
- Not added: an Unskip button in admin.
- Raised by David while testing: changing the interval kept the old next date, so going from every 4 weeks to weekly still waited the 4 weeks. `Changes.RescheduleForInterval` on `:change` now counts the new interval from the last delivery on the old schedule (next minus old interval, plus new interval), and steps along the new schedule out of the charge window. Changing only the size keeps the date.
- Follow-up: deriving the last delivery as "next minus old interval" broke on a subscription whose interval had changed before this fix (weekly, next date still 4 weeks out). Every later change then counted from a date nothing was delivered on. The anchor is now the `last_delivery_date` aggregate (latest placed, non-cancelled order), and it falls back to the derived date only for a subscription with no orders. David's dev subscription was repaired to Friday 16 October.
