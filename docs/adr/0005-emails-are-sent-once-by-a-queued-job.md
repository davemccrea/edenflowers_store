# Emails are sent once by a queued job

Every email the shop sends in the background is one Oban job with a few attempts: an AshOban trigger when it's about a record, a plain `Oban.Worker` when it isn't. Queuing it means "send this once". No scheduler looks for unsent emails, so nothing has to stop a scheduler sending an email Jennie chose not to send, and nothing retries an email for days.

A job that fails reaches ErrorTracker, which emails the error alert address the first time an error appears, and a developer retries the job from `/oban`. That's the only failure path most emails need.

An email gets a failure field and a resend control only when Jennie would do something about a failure herself, and only where she'd see it.

## Considered Options

- **A recovery scheduler for each email**, re-queuing any record without an `_emailed_at`. Rejected: an email that can never send is retried indefinitely, and each email needed a skip flag so the scheduler wouldn't send one Jennie had chosen not to send.
- **A failure field and resend control on every email.** Rejected: most emails have nowhere Jennie looks, or nothing she'd do differently from a developer retrying the job.

## Consequences

- An email that runs out of attempts is not sent until someone sends it again. The error alert email is how a developer finds out.
- An AshOban trigger's `where` is only for checking the email still makes sense when the job runs, such as the payment-failed email skipping an order already paid. It isn't for deciding whether to queue the email.
- Emails sent on a date, like course reminders, are scheduled by that date, not by looking for what's unsent.
- A sign-in code that can't send stops retrying within about a minute, before the code expires.
