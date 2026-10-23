---
id: TASK-105
title: 'Send one customer email per job, in Jennie''s voice'
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every customer email has one job, says what happened before anything else, and sounds like Jennie unless it only confirms something routine the customer did themselves.

**Why:** Emails that switch between different messages by state (order details as details, card refused or bill) are hard to reason about and to proofread in three languages. Customers get a clearer email for each thing that happens, and Jennie gets one way to add her own words.

Decided in a grilling session on 2026-10-23. Reverses the direction of `b2ab61e0` ("Send fewer kinds of email").

## Rules
1. **One email, one job.** A different message is a different email; a different detail (name present, pickup vs delivery, gift recipient, seats, payment method, an optional note) stays a variable. Duplicated wording between emails is fine.
2. **Jennie's voice is the default**, signed by her. Matter-of-fact and signed "Eden Flowers", from the automated address, only for: the customer's own cancellation, Subscription delivery charged, Already subscribed, sign-in and email-change codes. Automatic emails in Jennie's voice never pretend she did something by hand.
3. **Every email Jennie's action triggers has a tick box and a message box.** Her message sits after the line saying what happened, before the details, and is saved to the order log.
4. A payment link is introduced with "You can pay online here:".
5. Order subjects name the fulfillment date ("Your Eden Flowers order for Saturday 14.11."); booking subjects name the course and date.
6. A card or MobilePay refund line adds "It can take a few days to show on your statement" (matter-of-fact emails: "Refunds usually take 3–5 working days to appear on your statement."). A cash refund reads "I've refunded 20,00 € in cash."

## Emails
| Email | Trigger | Voice | Tick box |
|---|---|---|---|
| Order receipt | Online checkout paid | Jennie | none |
| Counter-sale receipt | Card sale in the shop with an email | Jennie | none |
| Order details | Custom order placed | Jennie | ticked |
| Order updated | Edit saved | Jennie | unticked |
| Payment received | Link or top-up paid; Jennie records a payment; menu item | Jennie, neutral for orders and bookings | unticked on recording |
| Payment reminder | Menu item while a balance is owed, not on invoice terms | Jennie | menu action |
| Delivered | Mark delivered | Jennie | ticked for gifts and when nobody was home |
| Left at the door | Mark delivered, nobody home, photo | Jennie | as Delivered |
| Cancellation confirmed | Customer cancels in their account | Matter-of-fact | none |
| Order cancelled | Jennie cancels | Jennie | ticked |
| Order refunded | Jennie refunds | Jennie | ticked for card/MobilePay, unticked for cash |
| Subscription set up | Subscription starts | Jennie | none |
| Subscription delivery charged | Each charge, 3 days before | Matter-of-fact | none |
| Subscription payment failed | Card declined | Jennie | none |
| Subscription cancelled | Jennie cancels a subscription | Jennie | ticked |
| Booking confirmed | Booking paid online | Jennie | none |
| Course payment link | Jennie adds or sends it, before the course | Jennie | ticked |
| Booking cancelled / refunded | As the order versions | Jennie | as orders |
| Newsletter welcome | New signup | Jennie | none |
| Already subscribed | Repeat signup | Matter-of-fact | none |

Removed: the bill version of Order details, the after-course course confirmation and payment link (Payment received and Payment reminder cover them). Unchanged: wedding enquiry copy (keeps "as soon as I can"), sign-in codes, shop notices.

Every email Jennie triggers shows a live preview in its drawer before it's sent (TASK-105.13).

Course cancellation terms and the course reminder are their own specs.
<!-- SECTION:DESCRIPTION:END -->
