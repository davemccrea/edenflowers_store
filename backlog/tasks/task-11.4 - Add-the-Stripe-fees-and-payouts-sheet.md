---
id: TASK-11.4
title: Add the Stripe fees and payouts sheet
status: ready-for-human
assignee: []
created_date: '2026-10-17 07:07'
updated_date: '2026-10-18 19:32'
labels: []
dependencies:
  - TASK-11.2
parent_task_id: TASK-11
type: feature
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Without it the accountant has to log into Stripe to book its fees and match payouts in the bank.

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
- [x] #1 The sheet lists the month's balance transactions, across more than one page of Stripe results
- [x] #2 Total fees and total paid out equal the sum of their rows
- [x] #3 A Stripe error gives an error flash and no download
- [x] #4 Tests stub `StripeAPI` and read the sheet back
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
StripeAPI.list_balance_transactions/2 follows pages through the stubbable callback list_balance_transactions_page/2, so tests cover pagination. Stripe sheet is the third sheet. Total fees = every row's fee plus Stripe's own fee rows (stripe_fee, stripe_fx_fee, tax_fee, application_fee), whose net is the fee. Paid out = minus the net of payout rows. Payout id is filled on payout rows only (the transaction's source); a charge's payout isn't on its balance transaction. Other transaction types show Stripe's raw type. Gross/Net headings are Brutto/Netto, not the VAT terms.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 19:32

---

Not yet run against a real Stripe account: download a month's report on staging (or locally with the test key) and check the Stripe sheet's rows and totals match the Stripe dashboard's balance report for that month.

---
<!-- COMMENTS:END -->
