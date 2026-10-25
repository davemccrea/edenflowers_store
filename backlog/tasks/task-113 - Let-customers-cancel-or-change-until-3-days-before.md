---
id: TASK-113
title: Let customers cancel or change until 3 days before
status: done
assignee: []
created_date: '2026-10-24 19:27'
updated_date: '2026-10-24 19:41'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers can cancel an online order, or pause, change or cancel a subscription, from their account until 3 days before its delivery or pickup. Subscriptions are charged 2 days before.

**Why:** Jennie only needs 2 days notice to buy flowers, so 5 days ties customers up for nothing. One short rule is also easier to say, and today the homepage says 4 days while the FAQ says 5.

Decided in grilling (2026-10-24):
- Change deadline: the last day to cancel or change is the fulfillment date minus 3. For a Friday, that is Tuesday.
- Charge day: 2 days before (`Subscription.@lead_days` 2). The change deadline must fall before the charge day, so `@cutoff_days` no longer equals `@lead_days + 1`. Pick the constants so `changes_open_for?/1` and the order self-cancel check (order.ex:1427-1437) both allow the date minus 3 and refuse the date minus 2.
- One-off online orders and subscriptions keep sharing one deadline, as CONTEXT.md says.
- Occurrences are created on the charge day, which is past the deadline, so a customer cannot cancel one from their account. Add a test for this.
- Heads-up email (`@heads_up_days`): keep its meaning, the day before changes close.
- Every customer-facing number comes from the constants: the homepage (home_live.ex:562 adds 1 to `lead_days`, so switch it to the change deadline), the FAQ, checkout ("charged N days before") and the subscription emails (email.ex:260, :339).
- Live subscriptions need no migration. Their next charge simply happens a day later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An online order can be cancelled from the account until its fulfillment date minus 3, and not after
- [x] #2 A subscription can be paused, changed or cancelled until 3 days before a bouquet, and its card is charged 2 days before
- [x] #3 An Occurrence can't be cancelled from the account
- [x] #4 Homepage, FAQ, checkout and emails state the new days from the constants; mix print_emails reviewed in sv, fi and en
- [x] #5 CONTEXT.md's Cancelled, Charge day and Change deadline entries say 3 and 2 days
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Subscription now has @lead_days 2 (charge day), @change_deadline_days 3 (last day to cancel or change) and @cutoff_days 2 (changes closed on and after the charge day). Resume and reschedule step to the first date still open to changes. Customer-facing copy reads change_deadline_days/0 and change_deadline/1. No msgids changed, so no gettext work.
<!-- SECTION:NOTES:END -->
