# Stock Tracking

Status: needs-triage

## Problem

Most of what Jennie sells is made to order, but a few things come in fixed numbers: add-ons she buys in (chocolates, vases, candles) and seasonal batches she makes up ahead (Christmas wreaths, Mother's Day bouquets), usually 5 to 50 of each. The store keeps selling them after they've run out, so she has to apologise and refund. Variants already have a `stock_quantity` and a "Limited stock" toggle in the product form, but nothing reads them.

## Decisions

1. **A blank `stock_quantity` means unlimited; a number means tracked.** Drop the `stock_trackable` column. The product form keeps a single "In stock" field; blank is unlimited.
   Rejected: keeping the boolean. It only adds a "tracked but blank" state to validate.

2. **`stock_quantity` is the count on the shelf and not yet promised.** Stock is taken when an order is placed, never when an item is added to a cart. There are no reservations.
   Rejected: holding stock in carts. That needs expiry, release jobs, and abandoned carts that keep stock tied up, all to guard against a rare race at this shop's traffic.
   Rejected: working out stock from orders, the way promotion usage is counted. A restock would then need to be recorded as its own entry.

3. **One shared change, `Changes.AdjustStock`, makes every stock movement.** It runs inside the action's transaction. For each tracked variant it locks the row (`FOR UPDATE`), then writes `max(count - n, 0)`. Variants are locked in id order. The lock means two orders placed at the same moment can't leave the count wrong, and the fixed order means they can't deadlock. Reading the count under the lock also gives the oversell check the count from before the update.
   - `finalize_checkout` and `place_custom` take the order's lines.
   - `cancel` puts the order's lines back.
   - `edit` puts the old lines back, then takes the new ones. It's the same change run twice, not a calculated difference.
   - Occurrences (`create_occurrence`, `place_unpaid_occurrence`) never touch stock. Subscription bouquets are florist's choice and made fresh.
   - Fulfilled orders are never adjusted, because `edit` and `cancel` already require `fulfillment_status == :pending`.

4. **An Online Order is placed even if it oversells.** The card has already been charged (automatic capture), and placed means committed (ADR 0001). The count floors at 0, and if the count before the update was below `n`, an error is logged so it reaches ErrorTracker, the same way `ReportPromotionOverused` does. Jennie either makes one more, or cancels the order and refunds it in Stripe.
   Rejected: rejecting the order after payment. That leaves money with no order behind it.
   Rejected: letting the count go negative. "-1 in stock" on the form is confusing.

5. **Custom Orders are never blocked and never logged.** Jennie knows what's on the shelf better than the count does. The count still goes down and floors at 0.

6. **Cancelling always puts stock back.** If she cancels because the item itself is lost (a damaged wreath), she corrects the count on the product form.
   Rejected: a "return stock?" choice in the cancel dialog. It's too rare to be worth it.

7. **Overselling is prevented as early as possible, in two places:**
   - A `LineItem` validation, `quantity <= variant.stock_quantity` when the variant is tracked, which covers `add_to_cart`, `increment_quantity` and `set_quantity`. The error reads "Only N left" or "Sold out".
   - The checkout payment step won't create a PaymentIntent while any line is over the current stock, and says which line it is. Lines are never changed or removed automatically.

8. **What customers see:**
   - Product page: a sold-out size is shown but disabled and labelled "Sold out", and the default selection skips it. If every size is sold out, add-to-cart is disabled.
   - Card drawer (`for_card_drawer`): sold-out cards are left out.
   - No "Only N left" message and no "Sold out" tag in the store grid. Add them when they're asked for.

9. **What Jennie sees:**
   - The product form sets an absolute count, never "+5". Saving sends the count shown when the form opened, so a sale made while it's open is undone and may oversell later (logged, per decision 4). This is accepted for simplicity. If it ever bites, send only counts Jennie changed.
   - The products list shows stock for tracked variants ("3 left", "Sold out").
   - No stock history and no low-stock alerts. Products have no version log, so once she edits the count, the previous value is gone.

## Proposed term

**Stock**: how many of a variant are on the shelf and not yet promised to a placed order. Only some variants have stock; the rest are made to order and unlimited.
_Avoid_: inventory, quantity on hand

Add to `CONTEXT.md` under Catalogue when this is picked up.
