---
id: TASK-136
title: Keep the buyer's and the gift recipient's phone numbers apart
status: done
assignee: []
created_date: '2026-10-27 19:37'
updated_date: '2026-10-27 20:12'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: bug
ordinal: 269000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A signed-in customer's own phone number stops being filled into a gift recipient's phone field at checkout, because orders store the buyer's and the recipient's numbers separately.

**Why:** a returning customer buying a gift gets their own number filled in as the recipient's, so Jennie would call the wrong person about the delivery. The one shared column also forces workarounds wherever the phone is read.

Online checkout stores the buyer's own number in recipient_phone_number, and the recipient's on a gift delivery. PrefillFromLastOrder copies it whenever the order isn't yet a gift delivery (gift chosen before a delivery option, or going back from For me), and nothing takes it off.

Decisions (grilled 2026-10-27):
- customer_phone_number is always the buyer's own number, on every order origin. recipient_phone_number is only a gift delivery recipient's; submit_gift_options and submit_delivery clear it otherwise.
- A contact_phone_number calculation (recipient's on a gift delivery, the customer's otherwise) is what readers use: receipt, confirmation page, admin order detail, missing_delivery_phone?.
- The delivery step keeps one phone field: recipient_phone_number on a gift delivery, customer_phone_number otherwise (gift pickup included, the buyer collects). Gift deliveries still don't ask for the buyer's number.
- Prefill fills customer_phone_number (and the address unless a gift delivery), never the recipient's.
- Stripe Link's billing phone comes from customer_phone_number.
- Subscriptions get the same split; activation and occurrences copy both.
- ClearGiftFields treats custom and online orders alike. The admin order form's prefill and the order detail's customer_phone? fallbacks go. User.phone_number reads customer_phone_number.
- Existing data moves by a one-off prod rpc after deploy (dry run, then write, after just backup), not a migration: on placed orders and subscriptions that aren't gift deliveries, move recipient_phone_number to customer_phone_number.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A signed-in customer whose last own order had their phone sees an empty recipient phone on a gift delivery, whether they chose the gift before or after the option, or went back from For me
- [x] #2 A For me or gift pickup order stores the phone in customer_phone_number and leaves recipient_phone_number empty
- [x] #3 A gift delivery stores the recipient's phone in recipient_phone_number
- [x] #4 Receipt, confirmation page, admin order detail and missing_delivery_phone? read contact_phone_number
- [x] #5 Subscriptions store both numbers and occurrences copy them
- [x] #6 A dry-run and write rpc command for moving existing orders' and subscriptions' phones is handed over
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decided after grilling: submit_delivery takes a single phone_number argument; a change writes it to customer_phone_number or recipient_phone_number, and the form shows contact_phone_number. No check constraint.

Also fixed: checkout's step forms were built without the actor, so submit_gift_options never prefilled from the page (only the default-option update did). Data move for production: SQL via Repo.query! over rpc, tested on dev. Run after deploy, after just backup.

Also fixed the address leak: set_gift clears the delivery fields when the gift choice actually flips, since the address entered so far was for the other person. Going back to For me refills the Customer's own address on entering delivery.

Production data move (run straight after deploying, after just backup). It covers every online and subscription order in any state, not only placed ones, so carts already at payment before the deploy are fixed too. Only a cart paid in the minutes between deploy and running this would send its receipt without a phone.

Dry run:
ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'IO.inspect(Edenflowers.Repo.query!(~S|SELECT count(*) FROM orders WHERE origin = ANY(\$1) AND recipient_phone_number IS NOT NULL AND customer_phone_number IS NULL AND NOT (gift AND fulfillment_method = \$2)|, [~w(online subscription), ~S|delivery|]).rows, label: ~S|orders|); IO.inspect(Edenflowers.Repo.query!(~S|SELECT count(*) FROM subscriptions s JOIN fulfillment_options f ON f.id = s.fulfillment_option_id WHERE s.recipient_phone_number IS NOT NULL AND s.customer_phone_number IS NULL AND NOT (s.recipient_name IS NOT NULL AND f.fulfillment_method = \$1)|, [~S|delivery|]).rows, label: ~S|subscriptions|)'"

Write:
ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'IO.inspect(Edenflowers.Repo.query!(~S|UPDATE orders SET customer_phone_number = recipient_phone_number, recipient_phone_number = NULL WHERE origin = ANY(\$1) AND recipient_phone_number IS NOT NULL AND customer_phone_number IS NULL AND NOT (gift AND fulfillment_method = \$2)|, [~w(online subscription), ~S|delivery|]).num_rows, label: ~S|orders|); IO.inspect(Edenflowers.Repo.query!(~S|UPDATE subscriptions s SET customer_phone_number = s.recipient_phone_number, recipient_phone_number = NULL FROM fulfillment_options f WHERE f.id = s.fulfillment_option_id AND s.recipient_phone_number IS NOT NULL AND s.customer_phone_number IS NULL AND NOT (s.recipient_name IS NOT NULL AND f.fulfillment_method = \$1)|, [~S|delivery|]).num_rows, label: ~S|subscriptions|)'"

Codex review fix: the admin order form showed a recipient phone field on online orders that are not gifts (the old workaround), and ClearGiftFields then dropped whatever Jennie typed there. The field now shows only for gifts; the customer phone field holds the buyer number.
<!-- SECTION:NOTES:END -->
