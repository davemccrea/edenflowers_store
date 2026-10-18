---
id: TASK-33.3
title: >-
  Put the payment choice and the only Place order button at the bottom of the
  custom order form
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:56'
labels: []
dependencies: []
parent_task_id: TASK-33
type: feature
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** On desktop the payment choice sits in the right column and is easy to miss, and there are two Place order buttons, one in the header. Jennie should read the form top to bottom and finish at one button.

In `order_form_live.ex`, move the Payment section into the main column after Recipient and card, on every screen size, and remove the header submit button. The Florist note can stay in the side column.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Payment is the last section before the submit button on desktop and mobile
- [x] #2 The form has one submit button, at the bottom
<!-- AC:END -->
