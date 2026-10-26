# Emails are sent once by a queued job

Every email the shop sends in the background is one Oban job with `max_attempts 3`: an AshOban trigger with `scheduler_cron false` when it's about a record, a plain `Oban.Worker` when it isn't. Queuing it means "send this once". No scheduler looks for unsent emails, so nothing has to stop a scheduler sending an email Jennie chose not to send, and nothing retries an email for days.

A job that fails reaches ErrorTracker, which emails the error alert address the first time an error appears, and a developer retries the job from `/oban`. That's the only failure path most emails need.

An email gets a `<email>_failed_at` field, set by the trigger's `on_error`, only when Jennie would do something about a failure herself. Today that's the receipt, the custom order details and the fulfillment confirmation. Each of these shows a warning on the order page and has a menu item to send it again. A course booking's confirmation has a resend item on the booking row but no failure field, since bookings have no history to show one. The other emails rely on the developer path.

## Considered Options

- **A recovery scheduler for each email**, re-queuing any record without an `_emailed_at`. Rejected: an email that can never send is retried indefinitely, and each email needed a skip flag so the scheduler wouldn't send one Jennie had chosen not to send.
- **A failure field and resend control on every email.** Rejected: most emails have nowhere Jennie looks (course bookings have no history) or nothing she'd do differently from a developer retrying the job.

## Consequences

- An email that fails 3 times is not sent until someone sends it again. The error alert email is how a developer finds out.
- An AshOban trigger's `where` is only for checking the email still makes sense when the job runs, such as the payment-failed email skipping an order already paid. It isn't for deciding whether to queue the email.
- A sign-in code that can't send stops retrying within about a minute, before the code expires.

## Course booking consequences (TASK-133)

Manual entry queues the ordinary booking confirmation only when Jennie keeps
Email booking confirmation ticked, true by default, and keeps her optional
message. Website payment queues that confirmation when it first confirms the
pending checkout. A later Payment Link payment queues Payment received, never
the original booking confirmation. Explicit collection remains a manual action;
there is no automatic Invite email or Invite template.

Confirmation and receipt stamps differ: a successful unpaid confirmation stamps
only `confirmation_emailed_at`; an actual attached receipt also stamps
`receipt_emailed_at`. Sender and drawer preview make the same actual-money
decision. Customer receipt downloads use the same financial eligibility rather
than treating confirmed as paid. Reminders still run daily at 07:00 Finnish time
for tomorrow's confirmed bookings, including unpaid ones, stating any Balance and
the chosen payment instructions. Cancelled/pending bookings do not get attendance reminders or
normal confirmation. Payment reconciliation and these email queues remain; only
the obsolete registration-purge scheduler/worker was retired. See
[rollout instructions](../purchase-retention-rollout.md) for queued old jobs.

Manual booking entry now offers the same terms as Custom Orders: Payment Link,
Invoice, or In person. Choosing Payment Link creates it when the booking is
accepted; the optional confirmation includes it and stamps it as emailed only
after successful delivery. Invoice means Jennie handles invoicing elsewhere,
never that money was received. Confirmation and attendance reminders follow
those terms rather than always asking for payment at the course.
