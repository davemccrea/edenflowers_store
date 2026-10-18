---
id: TASK-6.1
title: Pick which dev fixtures to cut
status: ready-for-human
assignee: []
created_date: '2026-10-10 22:45'
updated_date: '2026-10-18 05:08'
labels: []
dependencies: []
parent_task_id: TASK-6
type: task
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`priv/repo/seeds.exs` is ~1,250 lines of fixtures on top of `priv/repo/seeds/production.exs`. Each block exists to put an admin or storefront screen into a particular state. Mark the ones you never look at; the rest stay.

| Keep? | Fixture | What it shows |
|---|---|---|
| | 6 bouquets, 4 plants, 4 pre-loved | Store grid and category ribbon |
| | 4 cards | Card drawer at checkout |
| | Florist's choice bouquet (3 sizes, subscribable) | Subscribe flow, free delivery |
| | SUMMER15 + ended / not started / used-up promotions | Promotion code at checkout, admin promotions list states |
| | Expenses (ingested receipts) | Admin expenses list and detail |
| | Courses: upcoming ×3 (one empty), one past | Course booking, admin courses page |
| | Course registrations: pending, cancelled, added by Jennie, dropped out | Admin registrations, who still owes |
| | Placed orders (~12): delivery vs pickup, gift, promotion, big cart, locales, fulfilled | Dashboard open/completed split, order detail variety |
| | Subscriptions, one per state, with occurrences | Admin subscriptions list, account page |
| | Custom orders: phoned-in funeral, walk-in MobilePay, made smaller + refunded, fulfilled unpaid, cancelled | Order log, balances, payment links |
| | Online order edited after paying (Erik) | Balance to collect via payment link |
| | Part-paid custom order | Partial balance |
| | Refunds: in full, not yet refunded, out of stock, cash change | Refund states in order detail |
| | Collected and paid by card at counter | Zettle in-person payment |
| | Free replacement | Zero-total order |
<!-- SECTION:DESCRIPTION:END -->
