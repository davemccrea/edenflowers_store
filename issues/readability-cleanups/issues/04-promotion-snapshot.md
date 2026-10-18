# Snapshot an order's promotion as one embedded value

Status: needs-triage
Type: refactor

## Problem

An order copies its promotion into five attributes (`promotion_id`, `discount_rate`, `promotion_name`, `promotion_code`, `promotion_minimum_cart_total`), so the receipt keeps the terms the order was placed under. Every place that sets or clears the promotion has to list all five: `clear_promotion`, `ApplyPromotion`, `ResetCheckout`, and anything reading them.

## The idea

One embedded `promotion_snapshot` (an `Ash.Resource` embedded type with name, code, rate and minimum), next to `promotion_id`. Setting and clearing become one attribute, and the snapshot's shape is defined in one place.

## To decide

- Is the migration worth it for five fields? It needs a data migration of existing orders, and every expression reading `discount_rate` (`promotion_applied?` on the order, the line discount in `LineItem` at `order.discount_rate`) has to read the embedded field, which Ash expressions handle less comfortably than a column.

## Comments
