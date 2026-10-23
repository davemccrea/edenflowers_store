---
id: TASK-108
title: Remind subscribers before the change deadline
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 18:52'
labels:
  - spec
  - customers
dependencies: []
priority: low
type: feature
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A heads-up to subscribers on 2- and 4-week subscriptions the day before their next delivery's change deadline.

**Why:** A subscriber away on a delivery day only finds out once the card is charged, after changes have closed.

Decided in the email grilling session on 2026-10-23. Goes 6 days before delivery: the day before the change deadline (5 days before), so the customer has two days to act. Not for weekly subscriptions, nor while paused. Resuming doesn't send one. No setting to switch it off. Matter-of-fact, signed Eden Flowers, from the automated address:

```
Subject: Your next flowers come on Saturday 28.11.

Your next Florist's choice delivery is on Saturday 28.11.2026, to Esplanadi 1, Helsinki.   (pickup: ready to collect on …)

Away, or want a change? Pause or change it in your account by Monday 23.11.:
https://…/account

Your card will be charged 59,00 € on Wednesday 25.11.

Eden Flowers
```

Sent once per delivery by a queued job (ADR 0005).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Active 2- and 4-week subscriptions get the email 6 days before each delivery
- [ ] #2 Weekly and paused subscriptions get none
- [ ] #3 The email names the change deadline and the charge day and amount
- [ ] #4 Previews on the admin Emails page cover delivery and pickup, and the copy is translated in en, fi and sv
<!-- AC:END -->
