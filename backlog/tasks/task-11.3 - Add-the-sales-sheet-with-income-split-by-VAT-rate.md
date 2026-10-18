---
id: TASK-11.3
title: Add the sales sheet with income split by VAT rate
status: ready-for-agent
assignee: []
created_date: '2026-10-17 07:07'
updated_date: '2026-10-18 07:28'
labels: []
dependencies:
  - TASK-11.2
  - TASK-12.1
  - TASK-12.2
  - TASK-12.3
  - TASK-12.4
  - TASK-12.5
parent_task_id: TASK-11
type: feature
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The accountant needs income split by VAT rate for the VAT return, and payments are the shop's only sales record.

### What to build

Add the Försäljning (sales) sheet: every payment received in the month, split by VAT rate, with per-rate totals the accountant copies into the VAT return. This report is the shop's only sales record (ADR 0004), so every payment method counts. See decisions 3 and 4 in `TASK-11`.

- **Payments:** every `Payment` with `paid_at` in the month, for orders and course bookings (Helsinki boundaries), refunds included as negative amounts. Split each payment across its order's `vat_breakdown` rates, by each rate's share of the order's gross. Round each share to the cent and put any leftover cent on the rate with the largest gross, so a payment's rows always sum to its amount. Net and VAT for each row are worked out from its gross and rate.
- **Course payments:** a `Payment` on a course registration is one row at the registration's `tax_rate`, with no split.
- **Columns:** payment date, reference (`order_reference` or the registration's `reference`), source (beställning/kurs), payment method, VAT rate, net, VAT, gross. Sorted by payment date.
- **Below the rows:** totals per VAT rate (net, VAT, gross), and a grand total.
- Headings and payment method names in Swedish, through gettext (decision 7).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A one-payment order with a 25.5% product and a 13.5% delivery fee gives two rows matching its `vat_breakdown`
- [ ] #2 A partial payment and a refund are split in the order's proportions, and each payment's rows sum to its amount to the cent
- [ ] #3 A payment made just after midnight Helsinki time on the 1st belongs to the new month
- [ ] #4 Zettle, MobilePay, cash and Zervant payments are all included in the totals
- [ ] #5 Course payments and course refunds appear, dated by their `paid_at`
- [ ] #6 An in-person refund on a cancelled order (`TASK-12.4`) appears as a negative row
- [ ] #7 Per-rate totals equal the sum of their rows
- [ ] #8 Unit tests for the split and rounding, including a three-rate order where shares don't round evenly
<!-- AC:END -->
