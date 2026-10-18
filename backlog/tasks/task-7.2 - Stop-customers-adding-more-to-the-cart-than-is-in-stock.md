---
id: TASK-7.2
title: Stop customers adding more to the cart than is in stock
status: done
assignee: []
created_date: '2026-10-11 12:26'
updated_date: '2026-10-18 07:27'
labels: []
dependencies:
  - TASK-7.1
parent_task_id: TASK-7
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Stop customers putting more of a tracked variant in their cart than is in stock, and show sold-out sizes honestly on the storefront.

Any change to a cart line's quantity (adding, incrementing, setting) is refused when it would take the line above the variant's stock, with an "Only N left" or "Sold out" message the customer sees. On the product page, a sold-out size is shown disabled and labelled "Sold out", the default selection skips sold-out sizes, and add-to-cart is disabled when every size is sold out. The checkout card drawer leaves out sold-out cards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Adding, incrementing or setting a cart line above a tracked variant's stock fails with "Only N left" (or "Sold out" at 0), and the customer sees it.
- [x] #2 Untracked variants have no cap.
- [x] #3 On the product page, sold-out sizes are disabled and labelled "Sold out", and aren't selected by default.
- [x] #4 When every size is sold out, the product page's add-to-cart is disabled.
- [x] #5 The card drawer doesn't offer sold-out cards.
- [x] #6 New strings are localised (en, fi, sv).
<!-- AC:END -->
