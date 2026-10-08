# Subscription detail page

Status: ready-for-agent

The subscriptions table is the only admin table without a detail page: it has Pause/Resume/Cancel buttons in each row and its customer link goes to the customer. Give subscriptions a detail page like every other record (spec rule 8 and 9).

## What to build

- Route `/admin/subscriptions/:id` in the `:admin` live session, as `EdenflowersWeb.Admin.SubscriptionDetailLive`.
- Show what Jennie needs to service the subscription: customer (name, email, link to customer page), product variant and size, interval, next delivery date, state, fulfillment option, recipient and delivery address/instructions, card message, card on file (brand, last 4, expiry).
- Pause, Resume and Cancel move here from the table, with the same visibility rules and the same cancel confirmation.
- The subscription's orders (`has_many :orders`) as a Cinder table following the spec rules, like the customer detail order list.
- Match the layout of the existing detail pages (customer detail, order detail).

## Table changes

- Remove the Actions column from `subscriptions_live.ex`.
- Add `click` to the new detail page; the primary column links there instead of to the customer.

## Acceptance

- Clicking a subscription row opens its detail page.
- Pause/Resume/Cancel work from the detail page and the table has no buttons.
- Existing subscription admin tests move to the detail page; add one for the page rendering.
