---
id: TASK-33.3
title: >-
  Put the payment choice and the only Place order button at the bottom of the
  custom order form
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-21 21:07'
labels:
  - quick
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
- [ ] #1 Payment is the last section before the submit button on desktop and mobile
- [ ] #2 The form has one submit button, at the bottom
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @codex
created: 2026-10-21 21:07

---

Reopened after the 2026-10-22 commit audit. The sole Place order submit button is currently in the page header (order_form_live.ex), before the Payment section; AC #2 requires it at the bottom. Commit 2e39dabd updated that header button’s loading label, confirming the current placement. Payment remains the last section.

---

author: @codex
created: 2026-10-21 21:07

---

AC #1 also fails in the current layout: Payment is below the header submit button, so it is no longer the last section before submitting. This is a focused form-layout fix and has no open design decision.

---
<!-- COMMENTS:END -->
