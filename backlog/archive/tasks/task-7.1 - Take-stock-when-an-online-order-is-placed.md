---
id: TASK-7.1
title: Take stock when an online order is placed
status: done
assignee: []
created_date: '2026-10-11 12:26'
updated_date: '2026-10-18 08:25'
labels: []
dependencies: []
parent_task_id: TASK-7
type: feature
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Make stock real for the simplest path: Jennie sets how many of a variant are in stock, a customer buys some through checkout, and the count goes down.

A blank stock count means unlimited and a number means tracked, so the separate "limited stock" flag goes away and the product form keeps one "In stock" field. When an Online Order is placed, each tracked variant's count drops by the line quantity under a row lock, flooring at 0. If the count was already below the quantity (an oversell), the order is placed anyway and an error is logged, like the promotion overuse report. Build the stock movement as one shared change that the later issues reuse for Custom Orders, edits and cancels. The admin products list shows stock for tracked variants.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The `stock_trackable` column is dropped. A nil `stock_quantity` is unlimited and existing untracked variants stay untracked.
- [x] #2 The product form has one "In stock" field, where blank means unlimited.
- [x] #3 Placing an Online Order lowers each tracked variant's stock by the line quantity. Untracked variants are untouched.
- [x] #4 The decrement floors at 0, and two orders placed at the same moment can't leave the count wrong.
- [x] #5 An oversold Online Order is still placed and logs an error naming the order and the variant.
- [x] #6 The products list shows "N left" or "Sold out" for tracked variants.
<!-- AC:END -->
