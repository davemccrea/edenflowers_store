---
id: TASK-61
title: 'Record a customer email that failed to send, and let Jennie send it again'
status: done
assignee: []
created_date: '2026-10-19 07:58'
updated_date: '2026-10-19 20:12'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: high
type: feature
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customer emails that go out in the background retry a few times, then record the failure where Jennie sees the order or booking, and she can send them again.

**Why:** today a customer email that never sends either retries forever in silence or gives up in silence, so Jennie doesn't know a customer is missing their receipt or confirmation. The fulfillment confirmation also carries a lot of machinery for this (job-state inspection, polling, a skip flag, a retry action), and Jennie still can't send it if she unticked "email the customer" and changed her mind.

### Decisions

1. **Background email is a plain queued job.** Each email is one AshOban trigger run with `run_trigger`: `scheduler_cron false`, no `where` rule, `max_attempts 3`. A queued job means "send this once". No recovery scheduler, so no flag is needed to stop a scheduler sending what Jennie chose not to send.
2. **The send action records success, `on_error` records failure.** The send action sets `<email>_emailed_at` (and the recipient where it is shown) and clears the failure. The trigger's `on_error` names an update action that sets a nullable `<email>_failed_at`. AshOban passes the error as an `error` argument; the record doesn't keep it, since the errors page and the error alert already have it. One pair of fields per email, side by side, over one shared failure table: easier to read.
3. **Both outcomes show in the history and reach open pages.** The send and the failure actions are paper-trailed, so the log shows "… emailed" or "… failed". Both are published over the existing `Ash.Notifier.PubSub` on `["order", ..., :id]`, so an open order page reloads or flashes without polling.
4. **Jennie can always send it again.** An actions-menu item, "Email …" before a send and "Resend …" after one, with the same `confirm_send` prompt as receipts. It queues the job. It works whether the earlier send failed, was never asked for, or went out.
5. **A pending send isn't shown as a state.** After a reload, a queued send looks like a never-sent one (no history entry, "Email …" in the menu). Retries take seconds to a couple of minutes, so a status display isn't worth its code.
6. **Not in scope:** an Overview "Needs attention" list of failed emails (later, if Jennie misses failures on the order page), and receipts Jennie sends herself from the admin, which send while she waits and already flash any error.

Not in production yet: no queued jobs or old rows to keep compatible, so fields and triggers can be dropped and migrations generated freely.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Only the receipt, order details and fulfillment confirmation record a failure for Jennie. A course booking's confirmation has a resend item but no failure field. Every other background email relies on ErrorTracker and /oban (ADR 0005).
<!-- SECTION:NOTES:END -->
