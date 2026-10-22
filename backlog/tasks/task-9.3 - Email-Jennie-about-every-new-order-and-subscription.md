---
id: TASK-9.3
title: Email Jennie about every new order and subscription
status: ready-for-human
assignee: []
created_date: '2026-10-22 06:35'
updated_date: '2026-10-22 07:02'
labels: []
dependencies: []
parent_task_id: TASK-9
type: feature
ordinal: 186000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a push only arrives while a device stays subscribed, and Apple can drop one without telling us. An email to the shop's inbox is the backstop that doesn't depend on her phone.

### What was built

- Every new order and subscription emails `SHOP_NOTICE_EMAIL` (info@ on production), in Swedish: the title as subject, "Öppna i adminpanelen:" and the admin link as the body, plus the date and time first for an order with one.
- Sent for a paid checkout, a subscription's order (charged or card refused) and a new subscription. Not for Jennie's own custom orders.
- The push now sends the same titles in the device's language, with no body, for the same events, so both channels say the same thing.
- One change, `NotifyShop`, queues both; `Orders.ShopNotice` holds the wording.
- The admin re-saves the device's push subscription on every launch, so a server that dropped it (say after a one-off 404) gets it back.
- Unset `SHOP_NOTICE_EMAIL` (staging, as with `ERROR_ALERT_EMAIL`) sends no email, so test orders stay out of Jennie's inbox.

### Wording

| | Svenska |
|---|---|
| Order, another day | Ny beställning 1042 |
| Order, today | Leverans för idag 1042 / Avhämtning för idag 1042 |
| Subscription | Ny prenumeration |

On iOS a link in an email always opens Safari, not the home-screen app; only the push opens the app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A paid checkout emails the shop's inbox with a link to the order in the admin
- [x] #2 A subscription's order emails the shop whether its card was charged or refused
- [x] #3 A new subscription emails the shop with a link to it in the admin
- [x] #4 Staging, without SHOP_NOTICE_EMAIL, sends no shop email
- [ ] #5 Opening the installed admin re-saves a device's push subscription
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-22 06:36

---

Built and covered by tests. Left for a human: run the phoenix-ansible provisioning (adds SHOP_NOTICE_EMAIL to production) before deploying, or production sends no shop email; then check on Jennie's phone that reopening the app re-saves its subscription (#5).

---
<!-- COMMENTS:END -->
