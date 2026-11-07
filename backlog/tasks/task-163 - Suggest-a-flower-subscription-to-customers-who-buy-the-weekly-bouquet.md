---
id: TASK-163
title: Suggest a flower subscription to customers who buy the weekly bouquet
status: ready-for-agent
assignee: []
created_date: '2026-11-01 14:07'
updated_date: '2026-11-07 08:18'
labels:
  - customers
  - admin
  - spec
dependencies:
  - TASK-159
priority: medium
type: feature
ordinal: 303000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers who buy the weekly bouquet (or another subscribable product) for themselves are offered the same bouquet as a subscription, once, in the email that tells them it arrived.

**Why:** The relaunch plan (TASK-162) leads with the weekly bouquet, and subscriptions are where its buyers can go next, but nothing on the site or in the emails asks a one-off buyer to subscribe. Someone who has just received the weekly bouquet is the most likely subscriber the shop will ever have.

### What to build

One line and a link in the Delivered (`order_delivered.text.eex`) and Left at the door (`order_left_at_door.text.eex`) emails, under "Thank you for your order…" and before "Warm wishes".

Whether an order shows it is an Order calculation, `suggests_subscription?`, which the emails read. Nothing is stored. It is true when all of these hold:

- The order is not a gift and holds a product with `subscribable: true`.
- The customer has never had a Subscription, in any state (a cancelled one counts: they made a choice).
- It is the customer's first delivered order meeting the above that doesn't get the Google review ask (TASK-159's `asks_for_review?`). One ask per email: the review wins on the first order, and the subscription line goes on the next eligible one.

The link goes to the same product's page with `?subscribe=1`, which already opens it with subscribe preselected.

### Decisions (grilled 2026-11-01)

- **Delivered emails only.** No line on the order confirmation page (they haven't seen the flowers yet). Pickup orders get no Delivered email, so pickup buyers are not asked; Jennie can mention subscriptions in person.
- **No gifts.** The gift buyer never saw the bouquet, and subscribing would mean subscribing someone else.
- **No offer.** A plain line in Jennie's voice, no discount. A light mention of a similar product to an existing customer in a service email needs no marketing consent; a discount would push it towards that.
- **Wording.** English source: "If you'd like this bouquet to come again, you can have it delivered every week, every other week or every four weeks: <link>". Swedish draft for Jennie: "Vill du ha samma bukett igen? Du kan få den levererad varje vecka, varannan eller var fjärde vecka: <link>". Jennie approves the Swedish; Finnish follows it (see `priv/gettext/README.md`).
- **Blocked on TASK-159**, so the review rule is right from day one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Delivered and Left at the door emails suggest subscribing to the same product, linking to its page with ?subscribe=1, on a customer's first delivered non-gift order with a subscribable product that doesn't ask for a review
- [ ] #2 Customers who have or ever had a Subscription, gift orders and pickup orders never get the line
- [ ] #3 Whether an order suggests a subscription is an Order calculation, and the emails read it
- [ ] #4 The line reads naturally in sv, fi and en in mix print_emails (Swedish approved by Jennie), and Email.Previews has a scenario with and without it
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 19:13

---

Grilled 2026-11-01: Delivered emails only, no gifts, no pickups, no offer; never asked if ever subscribed; once, on the first eligible order without the review ask; link to the product with ?subscribe=1; derived Order calculation; blocked on TASK-159.

---
<!-- COMMENTS:END -->
