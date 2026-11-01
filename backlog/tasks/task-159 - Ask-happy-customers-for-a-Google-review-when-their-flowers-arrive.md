---
id: TASK-159
title: Ask happy customers for a Google review when their flowers arrive
status: needs-triage
assignee: []
created_date: '2026-10-31 20:30'
updated_date: '2026-11-01 19:13'
labels:
  - spec
  - customers
dependencies:
  - TASK-73
priority: high
type: feature
ordinal: 294000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Happy customers can leave Eden Flowers a Google review from the email that tells them their flowers arrived, and are asked only when it would feel natural.

**Why:** Google Maps reviews are what a local florist is chosen by, in the map pack for "florist Vaasa" and on the Business Profile (TASK-73). Right now nothing asks for one, so reviews come only from customers who think of it themselves.

### What to build

A short line under Jennie's thanks in the Delivered email (`order_delivered.text.eex`), in her voice, after the offer to put anything right. Something like: "If the flowers made someone's day, a few words on Google would mean a lot to me." It links to the profile's write-a-review URL (`https://g.page/r/<id>/review`), kept in `EdenflowersWeb.Business` next to `maps_url`.

### Tasteful means

- **Ask once.** Only on a customer's first delivered order, never again on later orders or on subscription Occurrences, which would turn it into a weekly nag.
- **Never after a death.** No ask on sympathy or funeral orders. Orders have no occasion today, so this needs a rule the domain can answer (an `asks_for_review?` calculation on Order), for example from the product's category.
- **Never if something went wrong.** No ask on an order with a Goodwill refund, or one Jennie edited after a complaint.
- **Not a prompt.** One sentence and a plain link. No stars, no "rate us", no offer in return (Google forbids incentivised reviews).
- **Left at the door** (`order_left_at_door`) asks the same way, since it is the same moment.

### Open questions

- How to tell a sympathy order: by category, by a flag on the product, or by Jennie unticking it on the order?
- Should the ask wait a day, so it lands after the recipient has had the flowers a while, as its own email? That needs consent rules checked; a line in an email the customer already gets does not.
- Swedish and Finnish wording is Jennie's call (see `priv/gettext/README.md`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Delivered and Left at the door emails ask for a Google review, linking straight to the review form, on a customer's first delivered order
- [ ] #2 No later order, subscription Occurrence, sympathy order or order with a Goodwill refund asks
- [ ] #3 Whether an order asks is an Order calculation, and the email reads it
- [ ] #4 The line reads naturally in sv, fi and en in mix print_emails, and Email.Previews has a scenario with and without it
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 19:13

---

TASK-163 depends on this: its suggests_subscription? calculation skips any order where asks_for_review? is true, so one email never carries both asks.

---
<!-- COMMENTS:END -->
