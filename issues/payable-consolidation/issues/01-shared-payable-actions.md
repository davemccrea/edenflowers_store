# Move the shared Stripe actions into Payable and call them by name

Status: ready-for-agent
Type: refactor

## What to build

Spec decisions 1 to 4.

- `mark_payment_cancelled`, `reconcile_payment` and `add_payment_intent_id` defined once in `Edenflowers.Payments.Payable`, removed from `Order` and `CourseRegistration`. The system-actor bypass for them moves with them, or stays listed per resource if a fragment bypass would weaken either resource's policy.
- A named change for "clear the PaymentIntent only if it's the one paid", used by both `record_link_payment` actions.
- `Edenflowers.Payments`: `cancel_payable/2`, `add_payment_intent_id/3` and the link-payment branch of `complete_payable/4` no longer branch per resource.
- Code interfaces: drop the `registration_`-prefixed duplicates where `Payments` was their only caller.

## Tests

- No new behaviour. `test/edenflowers/payments_test.exs`, `test/edenflowers/payments/*` and the order and course registration tests pass unchanged, apart from renamed interfaces.

## Acceptance criteria

- [ ] No action in the table in the spec is defined twice, apart from `record_link_payment` and `open_payment_link`
- [ ] `Payments` has no per-resource clause for cancelling, storing a PaymentIntent id or recording a link payment
- [ ] The existing suite passes

## Comments
