---
id: TASK-14.1
title: Give a goodwill refund on a fulfilled order or a booking
status: done
assignee: []
created_date: '2026-10-17 18:40'
updated_date: '2026-10-20 18:55'
labels: []
dependencies: []
parent_task_id: TASK-14
type: feature
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie can't refund an unhappy customer on a fulfilled order or booking without it reading as owed again.

### What to build

All of `TASK-14`: decisions 1 to 5.

- `goodwill` and a nullable `note` on `Payment` (generated migration), left out of `amount_paid` for the balance but counted by `refunded?`.
- A fragment action for Jennie's goodwill refund outside Stripe, and a `Payments` function that refunds an amount through Stripe and lets the webhook record it as goodwill.
- `record_stripe_refund` marking the part beyond what was owed back as goodwill.
- The "Refund" form in the order menu and the booking menu, with an optional reason; order log and payments list labels that show the reason.
- CONTEXT.md: add **Goodwill refund**. `TASK-13` decision 3 gets a pointer here.
- New copy through gettext, with en, fi and sv msgstrs.

### Tests

- Fragment, for both: a part and a full goodwill refund on a settled record leave it settled; the full one reads refunded; one above what was received, or above `paid_outside_stripe` outside Stripe, is refused; one while something is to collect is refused; it can be undone; its reason is kept when given.
- Stripe: a webhook refund on a settled record is goodwill and leaves it settled; one straddling what was owed back settles the owed part and marks the rest goodwill; the goodwill refund through Stripe sends the right amount spread over the Stripe payments.
- LiveView, on both pages: "Refund" shows only when allowed, and a part refund by Stripe and by cash each record and leave no "To collect".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every case above passes
- [x] #2 A fulfilled order refunded in the Stripe dashboard doesn't appear under "To collect" on the Overview
- [x] #3 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-17 18:40

---

- Before building: decide whether a goodwill refund asks for a reason shown in the order log (`TASK-14` open question). Set to `ready-for-agent` once decided.

---

author: @claude
created: 2026-10-19 13:55

---

Decided on 2026-10-19: no reason field (TASK-14 decision 5). Jennie writes the reason in an order's Florist Note; a booking's goodwill refund records none.

---

author: @claude
created: 2026-10-19 13:56

---

Changed on 2026-10-19: a goodwill refund takes an optional reason after all, as a note on Payment (TASK-14 decision 5), not the Florist Note.

---

author: @claude
created: 2026-10-19 14:17

---

Built on 2026-10-19. Two calls made before building: an order offers Refund whenever it's placed and not cancelled, fulfilled or not (decision 2 as written, over Out of scope); and once a price drops below what was paid after a goodwill refund, only money still held above the price is owed back. Refunds made here carry a reason (owed or goodwill) in Stripe metadata, so only a dashboard refund is split by the balance.

---

author: @claude
created: 2026-10-20 18:55

---

Since TASK-60 and TASK-79 (3d0fd5ad), the Refund in the order menu and the booking menu opens goodwill_refund_form in the page's settlement drawer instead of showing it inline.

---
<!-- COMMENTS:END -->
