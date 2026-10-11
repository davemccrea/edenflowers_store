# Online orders take stock

Status: done

## Parent

`.scratch/stock-tracking/spec.md`

## What to build

Make stock real for the simplest path: Jennie sets how many of a variant are in stock, a customer buys some through checkout, and the count goes down.

A blank stock count means unlimited and a number means tracked, so the separate "limited stock" flag goes away and the product form keeps one "In stock" field. When an Online Order is placed, each tracked variant's count drops by the line quantity under a row lock, flooring at 0. If the count was already below the quantity (an oversell), the order is placed anyway and an error is logged, like the promotion overuse report. Build the stock movement as one shared change that the later issues reuse for Custom Orders, edits and cancels. The admin products list shows stock for tracked variants.

## Acceptance criteria

- [x] The `stock_trackable` column is dropped. A nil `stock_quantity` is unlimited and existing untracked variants stay untracked.
- [x] The product form has one "In stock" field, where blank means unlimited.
- [x] Placing an Online Order lowers each tracked variant's stock by the line quantity. Untracked variants are untouched.
- [x] The decrement floors at 0, and two orders placed at the same moment can't leave the count wrong.
- [x] An oversold Online Order is still placed and logs an error naming the order and the variant.
- [x] The products list shows "N left" or "Sold out" for tracked variants.

## Blocked by

None - can start immediately
