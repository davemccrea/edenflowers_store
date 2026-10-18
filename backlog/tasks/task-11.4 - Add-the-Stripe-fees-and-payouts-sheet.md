---
id: TASK-11.4
title: Add the Stripe fees and payouts sheet
status: ready-for-agent
assignee: []
created_date: '2026-10-17 07:07'
updated_date: '2026-10-18 05:48'
labels: []
dependencies:
  - TASK-11.2
parent_task_id: TASK-11
type: feature
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Add the Stripe sheet so the accountant can book Stripe's fees and match its payouts in the bank without logging into Stripe. These rows are not sales; sales come from the Försäljning sheet. See decision 8 in `TASK-11`.

- **Stripe client:** a new function on `Edenflowers.External.StripeAPI` that lists balance transactions created in a time range, auto-paginating. Call it through `StripeAPI.impl()` so tests can stub it, as the other functions are.
- **Range:** the month's Helsinki midnight boundaries, as UTC timestamps.
- **Columns:** date, type (charge, refund, payout, fee, adjustment, in Swedish through gettext), description, gross, fee, net, payout id. Amounts converted with `StripeAPI.from_stripe_amount/1`. Sorted by date.
- **Below the rows:** total fees and total paid out to the bank.
- **Errors:** if Stripe can't be reached, `MonthlyReport.build` returns an error and the download fails with an error flash, as for receipts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The sheet lists the month's balance transactions, across more than one page of Stripe results
- [ ] #2 Total fees and total paid out equal the sum of their rows
- [ ] #3 A Stripe error gives an error flash and no download
- [ ] #4 Tests stub `StripeAPI` and read the sheet back
<!-- AC:END -->
