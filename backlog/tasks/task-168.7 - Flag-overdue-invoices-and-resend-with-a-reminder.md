---
id: TASK-168.7
title: Flag overdue invoices and resend with a reminder
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
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
- [ ] #1 Admin flags open invoices past their due date
- [ ] #2 Jennie can resend an invoice; the email gains a reminder line when it's overdue
- [ ] #3 No invoice email is sent automatically
<!-- AC:END -->
