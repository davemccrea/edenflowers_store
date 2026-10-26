# Retained purchases and manual course bookings (TASK-133)

This change separates a booking/order commitment from its money. It does not
deploy itself, repair previously deleted history, or set a legal retention period.
TASK-116 owns privacy/retention policy; no seven-year period is approved here.

## Before a production release

1. Obtain release approval. Run `just backup` and confirm the dump exists in `tmp/`
   before any direct production database inspection or modification. The normal
   `just deploy` workflow also takes a backup.
2. Review pending legacy Invites: `course_registrations` with `status = 'pending'`
   and a non-null `payment_link_token`. Do not automatically confirm them, count
   their places, delete them, or invalidate their issued links/intents. If any
   exist, stop the rollout until Jennie classifies each one and a separately
   approved, narrow transition preserves its actual commitment and money. A
   pending Invite is not evidence that she accepted a booking. No production
   review or transition was performed while implementing this issue.
3. Stop old application/Oban processes before migrations and restart with the new
   release, not a mixed-version rolling deployment. An old process already
   executing a delete cannot be stopped by changing a job's database state.
4. Apply the generated restrictive Payment-parent foreign-key migration. It
   changes constraints, not purchase/Payment data. Both real parent foreign keys,
   exactly-one-parent validation, Stripe uniqueness and reversal relationships
   remain. There is no archive migration.
5. The purge-retirement migration cancels only nonterminal jobs for
   `Edenflowers.Courses.Workers.DiscardAbandoned` and its scheduler. It does not
   remove job history or touch reconciliation, reminders or other email queues.
   Verify no old scheduler can create more purge jobs, then start the new release.

## Behaviour to verify

- A manual course booking is immediately confirmed, appears in normal bookings,
  and counts places, even if unpaid or over capacity. Default payment is at the
  course. An actual received payment has a real Payment row and method.
- Confirmation is optional, including Jennie's message. No money means no receipt
  attachment or receipt stamp. Paid/part-paid confirmation includes a receipt;
  a positive Balance is stated honestly. Unpaid confirmed bookings receive the
  ordinary day-before reminder. Explicit collection links settle Balances without
  booking places or sending the original confirmation again.
- Website checkout stays pending, retained and hidden from normal bookings until
  payment, with no temporary seat hold. Same-registration revision/retry remains.
- Custom Orders use cancellation and existing Still to do/All orders filtering,
  not deletion or an archive state. Financial attention is independent of that
  working-list filter. Cancelled parents still receive actual late Payments and
  refunds without being reopened, rebooked or restarting a subscription.
- Existing empty unused store-cart cleanup remains. No placed order or course
  registration has a normal hard-delete action.

## Recovery limits

Reconciliation still runs every ten minutes. It checks attached intents on parents
whose `updated_at` is older than five minutes and newer than seven days, including
cancelled parents. This is not indefinite Stripe-wide polling. Missing references
and older records need explicit developer recovery: verify the Stripe metadata
and parent, then use `Edenflowers.Payments.reconcile/1` on a record with its attached
intent, or `complete/1` with the retrieved succeeded intent. Follow backup-first
production procedures. Existing refund webhook/sync paths remain; no new scheduled
refund scanner or automatic late/mismatch refund was added.

A zero Balance is a point-in-time ledger result, not proof that no Stripe payment
is processing or no webhook was missed. Failed cancellation retains its intent;
an old cancellation cannot clear a replacement. Late money remains for Jennie's
ordinary settlement/refund workflow.

## Rollback

Do not blindly run an older application against new confirmed-but-unpaid manual
bookings: older code assumes confirmed means paid and can run destructive purge
jobs. A schema-only rollback also restores cascading Payment-parent deletion.
The purge-retirement migration deliberately never reactivates cancelled jobs.
Use the normal backup-first rollback procedure (`just rollback <previous tag>
<dump>`) only after assessing post-backup payments/orders and Stripe operations;
restoring a database cannot undo Stripe money and may require reconciliation.
Leaving the dump argument out keeps the data, but does not make old booking
semantics compatible. Stop old workers and resolve compatibility explicitly.
