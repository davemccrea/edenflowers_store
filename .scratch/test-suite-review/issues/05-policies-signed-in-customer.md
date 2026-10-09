# Signed-in customers are refused on catalogue/pricing writes and admin-only Order actions

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 4, gaps 3 and 4)

## What to build

The policy tests only try `actor: nil`. Add a signed-in non-admin actor (`generate(admin_user(admin: false))`) to the policy tests for Product, ProductVariant, ProductCategory, Promotion, TaxRate, FulfillmentOption and Course. Also check that a customer can't edit, cancel, record an in-person payment on, or open a payment link for their own placed order.

## Acceptance criteria

- [ ] Create, update and destroy as a customer each raise Forbidden on every resource listed above
- [ ] A customer is refused every admin-only action on their own placed Order
- [ ] Changing Product's `forbid_if always()` to `authorize_if actor_present()` makes a test fail

## Blocked by

None - can start immediately

## Comments

- `policies_test.exs` now tries a signed-in customer (`admin_user(admin: false)`) on create, update and destroy for Product, ProductVariant, ProductCategory, Promotion, TaxRate, FulfillmentOption and Course. It also tries edit, cancel, in-person payment and payment link on the customer's own placed Order. All were already refused, so no policy changed.
- Confirmed: changing Product's `forbid_if always()` to `authorize_if actor_present()` fails the three new Product tests.
- The edit test sends valid params, because `:edit` validations otherwise fail with Invalid before the policy runs.
