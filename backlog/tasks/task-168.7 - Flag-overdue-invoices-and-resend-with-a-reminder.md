---
id: TASK-168.7
title: Flag overdue invoices and resend with a reminder
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 23:06'
labels: []
dependencies:
  - TASK-168.4
  - TASK-168.5
parent_task_id: TASK-168
type: feature
ordinal: 321000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie chases late payers herself, so she needs to see who's late and a quick way to nudge them.

Add an overdue calculation (open and past its due date) and show it in admin. A "Resend" action emails the same PDF with a friendly reminder line added to the Invoice email. Nothing is sent automatically. Add the reminder variant to the email previews.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Admin flags open invoices past their due date
- [x] #2 Jennie can resend an invoice; the email gains a reminder line when it's overdue
- [x] #3 No invoice email is sent automatically
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Invoice gains overdue? (open, due date before today in Helsinki) and sendable? (open). Admin shows an Overdue badge and Send/Resend on every open invoice; the Overview's Payment overdue list now includes purchases with an overdue invoice (payment_overdue? reads invoice_overdue?, and an invoiced Balance waits for its invoice's own due date). Resend reuses :send; the email reads overdue? at send time and gains a reminder subject and line, same PDF. Each send is a paper trail version (invoices_versions, with message and reminder flag) so the order log shows every send, not just the latest sent_at. A test asserts no Oban trigger or worker sends invoices or credit notes.
<!-- SECTION:NOTES:END -->
