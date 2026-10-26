# Payments are records, not a column on the order

An order can be paid more than once: a custom order paid later, a balance left by editing an order after it was paid, a refund. A single `amount_paid` and `payment_method` on the order could hold one payment, and a webhook redelivery was only made harmless by refusing to pay an order twice. So each payment is now a `Payment` row (negative for a refund), the order's `amount_paid` is their sum, and the balance is the total minus that. A unique PaymentIntent id, and refund id, on the row is what stops Stripe's at-least-once delivery from counting money twice.

## Consequences

- Only money that moved is a row. A PaymentIntent waiting for the customer stays on the order as `payment_intent_id` and is cleared once paid, so a later payment link opens a fresh one for the balance.
- A succeeded payment is always recorded, even for an order cancelled or already paid in person; it is reported as an error so Jennie refunds it.
- Refunds made in the Stripe dashboard arrive through the `refund.created`/`refund.updated` webhooks, which the Stripe webhook endpoint must be subscribed to.
- Sales revenue counts payments by when the money moved, not orders by when they were placed.

## Amendment: course bookings

Course bookings kept their money as fields on the registration, so online bookings didn't record when they were paid and course refunds weren't recorded at all. A `Payment` now belongs to either an order or a course registration, exactly one, enforced by a check constraint, and the resource lives in the `Payments` domain. Every payment and refund on a booking, through Stripe or recorded by Jennie, is a row like an order's, and a registration has a balance like an order's. Two foreign keys were chosen over a polymorphic reference so the database keeps references and joins honest.

## Amendment: one ledger for orders and bookings

Orders and bookings recorded and settled their money with separate code written at different times, so they disagreed: an order's balance ignored cancelling while a booking's didn't, Jennie recorded a booking payment one way and an order payment another, and each admin page decided for itself what could be refunded. Recording and settling money is now one Ash fragment, `Edenflowers.Payments.Payable`, that both resources include: the same `balance`, `settled?`, refund limits and `record_payment` action. Each resource only says what it's still to be paid for (`total_due`, zero once cancelled) and whether money is owed on it at all (`committed?`). How money is taken stays per resource, because that does depend on what's sold: checkout, payment links, seat holds, saved cards and customer self-cancel. A fragment was chosen over a shared parent table so that payments keep their two honest foreign keys.

## Amendment: a checkout payment confirms whatever it lands on

Course checkout used to refuse a payment that didn't match the booking's price, so a customer who changed their places while paying had to throw the registration away and start again, which risked deleting one Stripe was still paying. A customer now changes the same unpaid registration, and its PaymentIntent is brought up to the new price before they pay again. A succeeded payment confirms the booking as it stands when the payment lands, as store checkout places an order, and a difference is reported as an error and left as a Balance for Jennie to collect or refund. Paying for one place and then changing to two before it lands books two places with one place's price still to collect. That is rare enough for one florist to settle by hand, and simpler than cancelling and replacing payments to keep amounts exact. A change that arrives after the payment confirmed the booking is refused at the database.

## Amendment: retained purchases and commitment separate from money (TASK-133)

The paid-only/manual-payment-link-only choices in TASK-120 and commit 715949c8
are superseded. Jennie accepting a booking is a commitment to provide places,
even while unpaid, just as saving a Custom Order commits the shop to make flowers.
Manual bookings confirm immediately, count places, default to payment at the
course and may exceed online cutoff/capacity. Initial and later received money
use the same `Payable.record_payment` action, methods, undo and refund behaviour
as orders. There is no paid flag disconnected from the ledger.

Website checkout still holds no places until payment; TASK-123's same-record
revision and accepted price-difference behaviour remain. A payment on an already
confirmed manual booking only changes its Balance, never confirms/counts places
or sends the original confirmation again. Optional booking confirmation and the
day-before reminder may go while unpaid. Only actual recorded money permits a
receipt attachment/stamp/download; unpaid copy states payment at the course.
Payment Links are explicit Balance collection, not Invites. No Invite workflow
or temporary website seat holds remain.

Normal actions and jobs retain placed orders and all course registrations. Two
restrictive Payment-parent foreign keys prevent erasing already-recorded money;
removing destructive application paths separately protects in-flight money. No
general locking framework, polymorphic parent, trigger framework or automatic
late/mismatch refunds are needed. Old empty unused store carts still purge.

Verified late success/refunds on cancelled purchases remain ledger entries and
Balance obligations, without reopening fulfillment, rebooking places or restarting
subscriptions. Cancellation clears an intent only after Stripe agrees and only
if that same ID is still attached. Failed/processing cancellation leaves it
recoverable; a successful payment conditionally clears only its own ID.

Reconciliation includes cancelled parents on the existing ten-minute cadence and
five-minute/seven-day `updated_at` window. Missing references/older records require
explicit recovery, not an indefinite guarantee. Settled means no money is owed
in the ledger now, not permanent Stripe finality. Refund webhook/sync remains;
no scheduled refund scanner was added. See [rollout and recovery](../purchase-retention-rollout.md)
for legacy-Invite classification, obsolete-job retirement, backup and rollback
compatibility. Operational retention is not a new legal retention period.
