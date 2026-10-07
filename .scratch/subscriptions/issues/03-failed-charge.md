# Handle a failed off-session charge

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

When the off-session charge for an occurrence is declined or needs authentication, the order is still placed: Jennie has committed to it, see ADR 0001. It is flagged unpaid, and the customer is emailed a Payment Link for it. The subscription moves to `payment_failed` and creates no further occurrences until the customer pays or updates their card. Paying the link reactivates it.

## Acceptance criteria

- [x] On `authentication_required` or a card decline, the occurrence is placed unpaid with a Payment Link opened, and the customer gets an email with the link.
- [x] The subscription becomes `payment_failed` and the occurrence trigger skips it.
- [x] When the Payment Link payment succeeds (existing webhook/reconcile path), the subscription returns to `active`.
- [x] Admin subscription list shows `payment_failed` clearly.
- [x] Tests use the Stripe mock for both error codes and the recovery.

## Blocked by

- `02-create-occurrences.md`

## Comments

**Built (slice 03)**

- `CreateOccurrence`: a `%Stripe.Error{code: :card_error}` (a decline or `authentication_required`) now runs `Order :place_unpaid_occurrence` and returns `:payment_failed`. The change then moves the date on and calls `AshStateMachine.transition_state(:payment_failed)`. It logs a warning, not an error.
- `Order :place_unpaid_occurrence` (transition `:payment` → `:placed`) does what `place_custom` does: it sets `ordered_at` and `order_reference`, snapshots VAT, runs `Changes.OpenPaymentLink`, and queues the new `:send_payment_failed_email` trigger. It is in the system bypass and the order log ("Placed, but the saved card was refused").
- New email `Email.payment_failed/2` and template `payment_failed.text.eex`, sent by `Changes.SendPaymentFailedEmail`. It shows the delivery date and address, the total and the payment link, and says the subscription is on hold until it is paid. The trigger has no cron and runs only while `origin == :subscription and payment_link_open? and is_nil(details_emailed_at)`. Sending sets `details_emailed_at`, so the admin order page shows "Resend payment link" and the order log shows "Payment link emailed".
- `Subscription`: the transitions are `:create_occurrence` (active → payment_failed) and `:reactivate` (payment_failed → active). The trigger's `state == :active` filter already skips a held subscription, and the AshOban worker re-checks it, so a job queued earlier cancels with `:trigger_no_longer_applies`.
- `Changes.ReactivateSubscription` runs on `Order :record_link_payment` for `origin: :subscription`. It reactivates the subscription when it is `:payment_failed`, in the same transaction as recording the payment. The webhook and `reconcile_payment` already reach `record_link_payment` for a placed order, so no other change was needed.
- Admin `/admin/subscriptions` shows state as a badge: "Payment failed" in red, "Active" in green.
- sv/fi translations for the 6 new strings.
- Tests in `create_occurrence_test.exs` (6 new, replacing the old "refused card" test): decline and authentication_required each place the order unpaid, open a link, move the subscription to payment_failed and send the email; a re-run doesn't charge (Mox expects one call) and doesn't email again; no further occurrences while held; paying the link through the webhook reactivates the subscription; a late payment skips dates that have passed. `subscriptions_live_test.exs` adds a payment_failed badge test.

**Decisions and deviations**

- I wrote a dedicated email rather than reusing the order-details email, because the customer needs to be told why they are paying and that the subscription is on hold. `details_emailed_at` is the "already emailed" marker, so the existing admin resend buttons work unchanged.
- Re-runs: once the order is placed, the job doesn't charge, place or email again. If it finds the occurrence placed and `unpaid?`, it moves the subscription to `:payment_failed`, which covers a crash between placing the order and updating the subscription.
- `:reactivate` moves `next_fulfillment_date` forward by whole intervals to the first date that hasn't passed. Without this, a customer who pays late would hit the "missed delivery" error log once for each date that passed while the subscription was held.
- The failed PaymentIntent isn't stored on the order. The payment link page opens a fresh PaymentIntent for the balance, as it does for a custom order.

**Open questions**

- Paying the link doesn't replace the saved card. The next occurrence charges the same card and may fail again. Updating the card belongs to slice 05.
- Any link payment on an occurrence of a held subscription reactivates it, even a balance payment on an older occurrence. This is rare. Tightening it means matching the order to the failed date.
- Jennie isn't alerted beyond the warning log, the unpaid flag on the order and the red badge. If she wants an email, log at error level instead.

