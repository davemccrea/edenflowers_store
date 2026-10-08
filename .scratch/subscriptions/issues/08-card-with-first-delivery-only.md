# Send the card with the first delivery only

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A gift subscription's card comes with the first delivery only. Today each Occurrence copies the subscription's `card_message`, so Jennie would write the same card for every delivery, while the customer paid for one card on the first order.

From now on an Occurrence gets no card message. It stays a gift, because the recipient is set, so fulfilment still treats it as one. The subscription keeps its `card_message` as a record of what was sent.

When the cart is a subscription, the checkout gift step says so: "The card comes with your first delivery."

Decided with the user over sending and charging a card every time. If customers ask for a card with each delivery, the follow-up is a new message per delivery, edited from the account page, not the same message repeated.

## Acceptance criteria

- [ ] `CreateOccurrence` no longer sets `card_message` on the Occurrence; it remains `gift` when the recipient differs from the customer.
- [ ] The checkout gift step shows "The card comes with your first delivery." only for a subscription cart.
- [ ] The set-up email, if it mentions the card, says the same.
- [ ] The notice is translated into sv and fi.
- [ ] Tests: an Occurrence has no card message but is still a gift; the notice is shown for a subscription cart and hidden for a one-off.
- [ ] Update CONTEXT.md if the Subscription or Occurrence entry mentions the card.

## Blocked by

- `06-opt-in-on-product-page.md` (it changes how a cart becomes a subscription)

## Comments

**Built (slice 08)**

- `CreateOccurrence` no longer passes `card_message`, and `card_message` is gone from `Order :create_occurrence`'s accept list. `SetGiftFromRecipient` still makes the Occurrence a gift. The Subscription keeps its `card_message`.
- Checkout gift step: "The card comes with your first delivery." shows at the end of the card section when `subscription?` is true (`data-testid="first-delivery-card"`), in the existing hint style (`text-base-content/70 text-sm`). The card section only shows for a gift, so the notice does too.
- Set-up email: the template didn't mention the card, so it adds the same line only when the subscription has a `card_message`.
- 1 new string, translated into sv ("Kortet kommer med din första leverans.") and fi ("Kortti tulee ensimmäisen toimituksesi mukana.").
- Tests: `create_occurrence_test.exs` asserts the Occurrence is a gift with no card message. `checkout_live_test.exs` shows the notice for a subscription gift and hides it for a one-off gift. `subscription_test.exs` checks the set-up email carries the line.

**Decisions**

- CONTEXT.md's Subscription and Occurrence entries don't mention the card, so it is unchanged.
