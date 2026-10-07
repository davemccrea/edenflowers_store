# Change size, frequency or card; set-up email

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

From the account page, a customer can change their bouquet size and how often it comes, and replace their saved card. Replacing the card uses a Stripe SetupIntent with the Payment Element, the same element checkout uses. Replacing the card on a `payment_failed` subscription makes it `active` again. The customer gets a "your subscription is set up" email when it activates.

## Acceptance criteria

- [ ] Size and interval changes respect the 24-hour cutoff and apply from the next occurrence.
- [ ] Card update stores the new payment method; a `payment_failed` subscription returns to `active`.
- [ ] A set-up email is sent once on activation (Oban trigger, like the existing order emails).
- [ ] All user-facing strings are translated.
- [ ] Tests cover changes, card update (Stripe mock), and that the email is sent exactly once.

## Blocked by

- `03-failed-charge.md`
- `04-manage-from-account.md`

## Comments

**Built (slice 05)**

- `Subscription :change` accepts `product_variant_id` and `interval_weeks`. It refuses a cancelled subscription, an interval outside 1/2/4, and the 24-hour cutoff (`Validations.SubscriptionChangesOpen`, so Jennie can still make the change). The new `Validations.SubscriptionVariant` allows only another non-draft size of the same product. `next_fulfillment_date` stays as it is. `CreateOccurrence` reads the variant and interval from the subscription each time it runs, so the change applies from the next Occurrence with no other code.
- Account page: each subscription that isn't cancelled and isn't inside the cutoff has a form with "Size" (the product's non-draft variants, plus the current one) and "How often", and a "Save changes" button. Every subscription that isn't cancelled has an "Update card" link, and it shows inside the cutoff too.
- Card update: there is a new page at `/account/subscriptions/:id/card` (`SubscriptionCardLive`). It opens a SetupIntent (`usage: off_session`, automatic payment methods, `metadata.subscription_id`) on the subscription's Stripe Customer. The page mounts the same `Stripe` hook as checkout, with `data-intent="setup"`, so the hook calls `confirmSetup` instead of `confirmPayment`.
- `StripeAPI` behaviour gains `create_setup_intent/2` (customer id, metadata) and `retrieve_setup_intent/1`.
- `Payments.setup_card_replacement/1` and `Payments.save_subscription_card/2` (takes a SetupIntent or its id, plus an actor). `save_subscription_card/2` runs `Subscription :replace_card`, which sets `stripe_payment_method_id`. If the subscription is `:payment_failed`, it then runs the existing `:reactivate`, so the dates step past any that have passed. The unpaid Occurrence and its payment link are not touched.
- Set-up email: the new `setup_emailed_at` column (migration `add_subscription_setup_email`). The AshOban trigger `:send_setup_email` has no cron and runs `where is_nil(setup_emailed_at)`. `:activate` queues it with `run_oban_trigger`, inside `finalize_checkout`'s transaction. `Changes.SendSubscriptionSetupEmail` sends `Email.subscription_set_up/1` (template `subscription_set_up.text.eex`) in the subscription's locale to the user's email, with a bcc to the shop. The email gives the size, how often, the address and the next date, says the first delivery's receipt comes separately and the card is charged a few days before each delivery, links to the account page, and is signed by Jennie.
- Policies: customers may now `:read` their own subscriptions, which the card page needs, and `:change` / `:replace_card` them. The admin bypass gains `:change`. The system bypass gains `:send_setup_email` and `:replace_card`.
- 16 new strings, translated into sv and fi.
- Tests: `test/edenflowers/orders/change_subscription_test.exs` (11 tests: the change keeps the next date, other-product and draft sizes refused, invalid interval, cutoff with admin bypass, cancelled and someone else's subscription refused, SetupIntent creation, card stored, payment_failed → active with date stepping, idempotent re-save, can't save to someone else's subscription, non-succeeded SetupIntent ignored). One set-up email test in `subscription_test.exs` (queued on activation, sent once, and a re-run cancels without a second email). Two in `account_live_test.exs` (change form, card link inside the cutoff). Three in `subscription_card_live_test.exs` (form with client secret, return URL stores the card and redirects, another user's subscription refused). One webhook test (`setup_intent.succeeded`).

**Decisions and deviations**

- The card is stored from both the return URL and the `setup_intent.succeeded` webhook. Both go through `save_subscription_card`, and saving the same card twice changes nothing. The return URL gives the customer an immediate "Your card has been updated." without waiting on the webhook. The webhook covers a customer who closes the tab during a redirect (3DS). On the return path the SetupIntent id comes from the URL, so the subscription is looked up as the signed-in customer, and policy stops anyone saving a card to someone else's subscription.
- The card page is separate from the account page, so the Payment Element and Stripe's redirect have a page of their own.
- `:replace_card` has no state check. The UI hides it for a cancelled subscription. If a late webhook stores a card on a cancelled subscription, nothing happens, and Stripe doesn't retry the webhook forever.
- The old payment method isn't detached from the Stripe Customer.
- The set-up email is only queued by `:activate` (no cron), so subscriptions created before this change won't be emailed when it is deployed.
- `ProductVariant.draft` defaults to `true`, so the size list always includes the current variant even if it is a draft. Seeded subscription sizes must be non-draft to be offered as alternatives.

**Manual setup**

- Stripe dashboard: subscribe the webhook endpoint to `setup_intent.succeeded` (added to `.scratch/stripe-webhooks/issues/01-enable-dashboard-events.md`).
- Manual check in dev: on the account page, choose Update card, use test card `4000002500003155` (asks for 3DS), and check the subscription's `stripe_payment_method_id` changes. Repeat on a `payment_failed` subscription and check it becomes active.

**Open questions**

- The optional "Upcoming delivery in N days — skip?" email from the spec was not built.
- Changing the delivery address still means cancelling and starting a new subscription, as the spec says.
