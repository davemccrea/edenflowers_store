# Review the test suite

Status: resolved

Review only. Don't edit any files. Write the report under `## Comments` below.

## Context

- Run `source .env` before any `mix` command.
- Tooling: ExUnit, Mox (`stub`/`expect`), PhoenixTest + LazyHTML for LiveView, Ash generators in `test/support/generator.ex`, and `DataCase`/`ConnCase` in `test/support/`.
- Read `CLAUDE.md` and `CONTEXT.md` (if present) so you use the project's domain terms.

## Steps

1. Run `mix test` once. Record the pass/fail counts, the runtime and the 10 slowest tests (`mix test --slowest 10`). Rerun with 2–3 random seeds to surface flaky or order-dependent tests.
2. Map the domains in `lib/edenflowers/` and `lib/edenflowers_web/` to their test files. List the domains, actions, changes, policies, workers and webhooks that have no tests or only thin ones. Rank them by risk. Money, payments, subscriptions, authorization and webhooks come first.
3. Read the tests themselves and look for:
   - **False confidence:** tests that pass even when the code is broken. Examples: assertions on the wrong thing, `assert {:ok, _}` without checking state, missing `refute` cases, mocks that return whatever the code expects.
   - **Over-mocking:** Mox expectations that restate the implementation instead of checking behaviour, and mocks at the wrong boundary (anything other than the external API).
   - **Brittleness:** tests coupled to markup, CSS classes, exact copy or private functions, when they should check user-visible behaviour.
   - **Flakiness:** `Process.sleep`, time and date dependence (especially Helsinki timezone and week/weekday logic), ordering assumptions, shared global state, `async: false` without a reason.
   - **Missing edge cases** on money paths: refunds, partial payments, duplicate or out-of-order Stripe webhooks, idempotency, subscription change and cancel races, tax and promotion rounding, and failure paths (Stripe errors, job retries).
   - **Ash-specific gaps:** policies tested only with the happy actor, validations and state-machine transitions with no negative cases, and calculations not tested at their boundaries.
   - **Setup noise:** duplicated setup that belongs in the generator, over-sized fixtures, tests you can't read on their own.
   - **Dead weight:** redundant, duplicate or trivially true tests that cost runtime and give no confidence. Also stray files such as `test/drawer_browser_check.html`.
4. For every finding you suspect is a false-confidence bug, check it. Briefly break the code under test (in a scratch copy you then revert) and confirm the test would still pass. Mark each finding CONFIRMED or SUSPECTED.

## Output

- **Summary:** the suite's health in 3–5 lines, including the run stats from step 1.
- **Findings:** ranked most severe first. Each one gives `file:line`, the problem, a concrete failure scenario (what bug would slip through) and the suggested fix in one line.
- **Coverage gaps:** the top 10 untested behaviours by risk, each with a test name or test sketch.
- **Deletions:** tests safe to remove or merge.
- Skip style nits unless they hurt readability. Prefer fewer, high-confidence findings over a long list.

## Comments

### Review — 2026-10-09 (agent)

#### Summary

- **Run stats:** 978 tests, 0 failures. A normal run takes 26–30s (about 22–25s async, 4.4s sync). The `--slowest 10` run took 58.5s because that flag adds per-test overhead. Seeds 0, 1, 12345 and 987 all passed, so no order-dependent failures turned up.
- **Slowest tests:** `subscriptions_live_test.exs:35` takes 3.0s, which looks like a cold first load of the sv-FI locale rather than the test itself. Next are `pay_live_test.exs:112` (0.73s), four checkout happy-path tests (0.41–0.52s each) and `format_test.exs:12` (0.41s, also a cold locale load).
- **Health:** good overall. The checkout, subscription Occurrence and promotion/VAT paths are tested at their boundaries. About 20 of the 26 mutations I tried were caught, including off-by-ones on usage limits, the minimum cart total, VAT rounding, the change cutoff, card-error handling and the admin gate.
- **Weak spots:** what survives clusters in three places. The refund and webhook retry paths are thin. Policy tests only try `actor: nil`, never a signed-in customer. The receipt controllers never check that they refuse unpaid orders.
- **Method:** each mutation was applied in a throwaway git worktree with its own test DB (`MIX_TEST_PARTITION=9`), and the full suite was run against it. The worktree and DB have been removed; nothing in the repo changed.

#### Findings (most severe first)

1. **CONFIRMED: a pending refund gets recorded as money returned.** `lib/edenflowers/payments.ex:186`, test `test/edenflowers_web/webhooks/stripe_handler_test.exs:395`.
   - **Problem:** with the `status: "succeeded"` guard removed from `record_refund/1`, the full suite still passes. The webhook test sends pending, then succeeded, then succeeded, and only checks that one refund row exists at the end. That passes whether the row was written on the pending event or on the first succeeded one.
   - **Failure scenario:** a refund that is created pending and later fails or is cancelled stays on the order as a negative Payment. The Balance then claims the customer was refunded. `refund_balance` would also subtract it once as pending and again as recorded, so it refunds too little.
   - **Fix:** after the `refund.created` pending event, assert that no refund row exists. Add a pending → `refund.updated` failed case that records nothing.

2. **CONFIRMED: the refund idempotency key is never checked.** `lib/edenflowers/payments.ex:300`, test `test/edenflowers_web/features/admin/order_detail_live_test.exs:252`.
   - **Problem:** replacing the key with `System.unique_integer()` passes everything, because the `create_refund` mock ignores its third argument (`_key`).
   - **Failure scenario:** the key is the only guard against two "Refund with Stripe" clicks racing each other. If it stops being stable, money is refunded twice.
   - **Fix:** in the mock, match the key as `"refund-#{order.id}-#{n}-#{pi}"` (pinned), and assert that a second call made before anything is recorded sends the same key.

3. **CONFIRMED: webhook "retry" answers are untested.** `lib/edenflowers_web/webhooks/stripe_handler.ex:54`, `:67`, `:102`.
   - **Problem:** changing any of these three `:error` returns to `:ok` passes the full suite. No test drives the handler down a path that fails to record.
   - **Failure scenario:** a temporary DB or enqueue failure during `payment_intent.succeeded`, `refund.*` or `setup_intent.succeeded` returns `:ok`. Stripe then never retries, and the payment or refund is silently lost until someone reconciles by hand. That is the opposite of what ADR 0002 describes.
   - **Fix:** reuse the `ALTER TABLE oban_jobs ADD CONSTRAINT … CHECK (false)` trick from `payments_test.exs:318` and assert that `handle_event` returns `:error` for `payment_intent.succeeded`. Do the same for a refund whose order update fails.

4. **CONFIRMED: policy tests only try `actor: nil`, never a signed-in customer.** `test/edenflowers/policies_test.exs:23–258`.
   - **Problem:** changing Product's `forbid_if always()` (`lib/edenflowers/catalog/product.ex:110`) to `authorize_if actor_present()` passes everything. The same blind spot covers Promotion, TaxRate, ProductCategory, ProductVariant, FulfillmentOption and Course.
   - **Failure scenario:** any logged-in customer could create a 100% promotion or change prices, and no test would fail.
   - **Fix:** for each resource, add one case with `actor: generate(admin_user(admin: false))` that expects `Forbidden`.

5. **CONFIRMED: any actor can read Payments, and no test notices.** `lib/edenflowers/orders/payment.ex:51`.
   - **Problem:** changing `authorize_if expr(order.user_id == ^actor(:id))` to `authorize_if always()` passes everything.
   - **Failure scenario:** a customer could read another customer's payments (amounts, methods, PaymentIntent ids) through any read path that doesn't go through Order.
   - **Fix:** add a test that Customer B reading Payment with Customer A's `order_id` gets `[]`, and that the owner sees their own payments.

6. **CONFIRMED: the order receipt PDF is served for unpaid orders.** `lib/edenflowers_web/features/checkout/receipt_controller.ex:9`.
   - **Problem:** dropping the `state: :placed, payment_status: :paid` match passes everything. The only test (`order_detail_live_test.exs:105`) fetches the receipt of a paid order.
   - **Failure scenario:** a custom order that hasn't been paid gets a "receipt" PDF showing it as paid.
   - **Fix:** add a `get ~p"/order/#{id}/receipt"` test on an unpaid placed order that expects 404.

7. **CONFIRMED: the course receipt is served for unconfirmed bookings.** `lib/edenflowers_web/features/courses/course_receipt_controller.ex:11`.
   - **Problem:** dropping the `status: :confirmed` match passes everything.
   - **Failure scenario:** a booking that is pending, or failed its payment, gets a receipt.
   - **Fix:** add a 404 test for a `:pending` registration.

8. **CONFIRMED: the course booking cutoff day is never tested.** `lib/edenflowers/courses/changes/reserve_seats.ex:45`.
   - **Problem:** letting bookings in one day after `register_before` passes everything. The tests only use `register_before: today - 2` (`course_registration_test.exs:93`, `:130`).
   - **Failure scenario:** an off-by-one on the closing day goes unnoticed, so bookings arrive the day after registration closed.
   - **Fix:** use the Helsinki today: `register_before: today` is accepted, `register_before: today - 1` is refused.

9. **SUSPECTED (reasoned, not reproduced): the date picker tests fail on the last evening of each month.** `test/edenflowers_web/components/date_picker_test.exs:32`, `:48`.
   - **Problem:** the expected month comes from `Date.utc_today()`, but `DatePicker` uses Helsinki time (`date_picker.ex:9`).
   - **Failure scenario:** between 21:00 and 24:00 UTC on the last day of a month, Helsinki is already in the next month, so the header assertion fails. I couldn't fake the clock to prove it, because `faketime` isn't installed.
   - **Fix:** take the expected month from `HelsinkiToday.today()`.

10. **Over-sync: about 16 test files run synchronously for no clear reason.** For example `sales_summary_test.exs`, `line_item_test.exs`, `create_occurrence_test.exs`, `fulfillment/changes/*_test.exs`, `calendar_view_model_test.exs`, `promotion_test.exs`, `reconcile_payment_test.exs`, `expense*_test.exs` and the email worker tests.
    - **Problem:** none of them use DDL or global env. Only `payments_test.exs` (an `ALTER TABLE`), the two error-tracker tests (`Application.put_env`) and `papra_handler_test.exs` have a reason.
    - **Impact:** together they cost about 4.4s per run, roughly 15% of it.
    - **Fix:** add `async: true` to each, and a one-line reason to those that must stay sync.

11. **Setup noise: the same fixtures are rebuilt in many files.**
    - **Problem:** six test files each define their own `placed_order`/`order_for` helper with identical "seed a payment, and for refunded seed a negative one" logic: `orders_live`, `order_detail_live`, `customers_live`, `account_live`, `order_live` and `dashboard_live`. The subscription `Ash.Seed.seed!(Subscription, …)` block is copied into at least six files. The `state: :payment` order with a line item and a PaymentIntent is copied into `payments_test`, `reconcile_payment_test` and `stripe_handler_test`.
    - **Failure scenario:** these copies drift apart when the schema changes.
    - **Fix:** add `Generator.placed_order/1` (with `paid:` / `refunded:`), `Generator.subscription/1` and `Generator.order_in_payment/1`.

12. **Minor brittleness: tests keyed on styling classes.**
    - **Problem:** a few assertions select on CSS classes: `.line-through` (`courses_live_test.exs:40`, `:50`), `.menu-disabled` (`order_detail_live_test.exs:94–96`), and `.admin-badge-success` / `.admin-badge-error` (`order_detail_live_test.exs:132`, `:145`, `subscriptions_live_test.exs:79`).
    - **Fix:** these break on a restyle; prefer `aria-disabled`, `data-status` or the visible text.

13. **Minor: test data that will go stale.** `subscriptions_live_test.exs` uses `next_fulfillment_date: ~D[2026-11-03]`, and the fulfillment calendar reset test seeds overrides for `~D[2026-12-25]` and `~D[2026-12-26]`.
    - **Failure scenario:** once these dates pass, any pruning or "overdue" logic either breaks the tests or makes them pass without testing anything.
    - **Fix:** use dates relative to the Helsinki today.

Aside (code, not tests): `PapraWebhook` (`lib/edenflowers_web/plugs/papra_webhook.ex`) checks the HMAC but never checks `webhook-timestamp` against a tolerance window. Standard Webhooks requires that check, and without it a captured delivery can be replayed forever.

#### Coverage gaps (top 10 by risk)

1. **Refund webhook, pending then failed:** `test "a pending refund that fails is never recorded"`. Send `refund.created` pending, then `refund.updated` failed, and assert no negative Payment exists and the Balance is unchanged.
2. **Webhook asks Stripe to retry on a recording failure:** `test "payment_intent.succeeded returns :error so Stripe retries when the order can't be updated"`. Use the CHECK(false) constraint on oban_jobs, assert `:error`, then drop the constraint and assert a redelivery places the order.
3. **Signed-in non-admin on catalogue and pricing writes:** `for resource <- [Product, Promotion, TaxRate, …]`, create, update and destroy with `actor: customer` and expect `Forbidden`.
4. **Signed-in non-admin on admin-only Order actions:** `test "a customer can't edit, cancel, record an in-person payment or open a payment link on their own placed order"`. These are only safe today because they fall through to `forbid_if state == :placed`.
5. **Refund idempotency key:** `test "two refund clicks send the same idempotency key"`. Capture the key from the `create_refund` mock on two `refund_balance/1` calls made before any refund is recorded.
6. **Payment read policy:** `test "customers read only payments on their own orders"`.
7. **Receipts for unpaid or unconfirmed payables:** `test "no receipt for an unpaid custom order"` and `test "no course receipt for a pending booking"`, each expecting 404.
8. **`setup_intent.succeeded` with a generic failure:** `test "returns :error when saving the card fails for a reason other than a cancelled subscription"`. Stub `retrieve_payment_method` to fail, or use the Ash error path.
9. **`refund_balance` when Stripe errors partway through:** `test "a create_refund error on the second payment keeps the first refund recorded and reports the error"`. Today only happy paths and the case where Stripe already holds the refunds are covered.
10. **Course booking cutoff day and `CheckoutCompleteController`:** `test "booking is open on register_before itself and closed the day after"`, plus a direct test that `/checkout/complete/:id` with `redirect_status=failed` flashes and redirects to `/checkout`. That branch is untested.

#### Deletions / merges

- **Merge:** `stripe_handler_test.exs:236–279` and `:470–484`. Three tests cover `payment_intent.payment_failed`, which is a one-line `:ok` no-op, so the "does not downgrade" test can't fail for any real reason. Keep one test that asserts the order and the booking are unchanged.
- **Delete or merge:** `stripe_handler_test.exs:297–316` ("unhandled events"). Both tests are trivially true. Keep one if you want the catch-all to stay covered.
- **Drop:** `Edenflowers.Repo.delete_all(Oban.Job)` in the setup of `stripe_handler_test.exs:13`. The test is async with a sandbox, so there is nothing to clear.
- **Strengthen, or delete as redundant:** `stripe_handler_test.exs:406` ("of a payment the shop doesn't know is ignored") only asserts `:ok`. Assert that no Payment row was written.
- **Already gone:** the stray `test/drawer_browser_check.html` no longer exists.

### Follow-up — 2026-10-09 (agent)

All findings split into tickets 02–15 and resolved. No app-code bugs turned up; the gaps were in the tests. Suite: 1021 tests, 0 failures.
