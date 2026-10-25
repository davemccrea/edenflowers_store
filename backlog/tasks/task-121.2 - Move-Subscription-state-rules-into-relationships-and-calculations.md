---
id: TASK-121.2
title: Move Subscription state rules into relationships and calculations
status: done
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 10:23'
labels: []
dependencies: []
parent_task_id: TASK-121
type: refactor
ordinal: 242000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The account page finds a subscription's unpaid and next occurrence with Enum.find/filter over the customer's orders, and works out charge and reopen dates with public helpers.

Add has_one :unpaid_occurrence and has_one :next_occurrence, calculations charged_on, changes_reopen_on and resume_date on Subscription, and changes_open? on Order (an occurrence). :mine's 'final delivery still on its way' filter uses next_occurrence. CancelOpenOccurrences uses changes_open?. reactivate_if_held moves into the actions that call it. Constants used by copy (lead_days, change_deadline_days) stay as functions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 subscription_manager and subscription_card_live load unpaid_occurrence and next_occurrence instead of filtering orders
- [x] #2 charged_on, changes_reopen_on, resume_date and changes_open? are calculations; the public date helpers they replace are gone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Relationship named booked_occurrence (the web's word for it). Also added next_delivery_date (nil unless active) and changeable?, used by the admin lists and the account drawer. Kept charged_on/1: checkout quotes it before the subscription exists. Kept reactivate_if_held/1: it is already domain code shared by two actions, not used by the web.
<!-- SECTION:NOTES:END -->
