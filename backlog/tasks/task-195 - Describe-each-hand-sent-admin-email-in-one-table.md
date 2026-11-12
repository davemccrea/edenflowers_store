---
id: TASK-195
title: Describe each hand-sent admin email in one table
status: needs-triage
assignee: []
created_date: '2026-11-12 06:22'
labels:
  - spec
  - developers
dependencies:
  - TASK-191
  - TASK-193
references:
  - docs/adr/0006-one-customer-email-per-job.md
  - lib/edenflowers_web/features/admin/email_drawer.ex
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers/orders/order/calculations/admin_menu_actions.ex
  - lib/edenflowers/email/preview.ex
  - lib/edenflowers_web/features/admin/order_log.ex
priority: low
type: refactor
ordinal: 360000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Adding an email Jennie can send by hand means adding one entry beside the email drawer, and a test fails if any part of it is missing.

**Why:** New hand-sent emails are frequent, and each one is a five-file edit by kind atom with nothing tying the pieces together. A missed clause only shows up as a `FunctionClauseError` when Jennie opens that drawer.

## Problem

One email kind is spelled out in these places:

- kind to action: `EmailDrawer.action/2` (ten clauses)
- kind to labels: `EmailDrawer.text/3`
- kind to flash, once per page: `sent_message/1` and `failed_message/1` (`order_detail_live.ex:929-938`, `course_detail_live.ex:482-488`)
- kind to preview: `Preview.order_email/3` and `booking_email/3`
- kind to availability: `AdminMenuActions`
- action to log title: `OrderLog.title/1` (`order_log.ex:112-156`)

`String.to_existing_atom(kind)` at the top of `EmailDrawer.open/4` feeds all of them.

## What to build

One table in the drawer module for kind to action, labels and flash wording. The preview comes from the action's own compose step (TASK-191), so `Preview` no longer needs a clause per kind. Availability stays a calculation in `AdminMenuActions` and the log title stays in `OrderLog`: both are keyed on the action and belong where they are.

It supports ADR 0006's "a new kind of news is a new email with its own builder, template and scenarios".

## Still to decide (grill before implementing)

- Whether this is still worth a task of its own once TASK-191 and TASK-193 land. It may fall out of them; if so, archive it as wontfix.
- Whether the flash wording belongs in the table or stays per page because orders and bookings word it differently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A hand-sent email kind's action, drawer labels and sent/failed flash are defined in one place, and neither the order page nor the course page has its own per-kind clauses
- [ ] #2 A test fails when an email kind lacks an action, labels, flash wording, a preview or a menu availability
<!-- AC:END -->
