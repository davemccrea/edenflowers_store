# Fixes from the ponytail audit and Ash idioms review

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Apply the findings from two reviews of the subscriptions feature (commits ebb1fae..566aedf): a ponytail over-engineering audit and an Ash idioms review. Behaviour stays as agreed in the spec and issues 01–08, apart from the bug fixes listed here.

## Acceptance criteria

### Bugs

- [x] **The paid order is always placed.** Starting the Subscription can no longer block `finalize_checkout`, not even on a database error (ADR 0002). Start it from an AshOban trigger on the placed order (origin `:online`, has a subscription line, no `subscription_id` yet), so a failure retries instead of rolling back. The set-up email still goes out once. Remove `ActivateSubscription`'s Ash-error rescue if the trigger makes it unnecessary.
- [x] **One timezone for "today".** Use a single "today in Europe/Helsinki" helper for every subscription date decision: the occurrence trigger's `where`, `:reactivate`, `:resume`, `changes_closed?`, `occur_unless_missed` and `first_open_day`. Give `:reactivate` and `:resume` one named change or function for the "next scheduled date not before X" step, with their different floors as an argument.
- [x] **The occurrence job doesn't overwrite concurrent changes.** Moving the date on and removing the date from `skipped_dates` become atomic updates, so a skip or change Jennie makes in admin while the Stripe call is in flight isn't lost.
- [x] **No crash on a stale id.** The account page fetches the subscription through `Orders.get_subscription(id, actor: user)`, as admin does, so a stale or forged id gives an error flash.
- [x] **`KeepSubscriptionAlone` returns errors.** Read and destroy failures become changeset errors, not raises or MatchErrors. Keep the notification pass-through.
- [x] **Saving the card doesn't depend on the caller.** `Payments.setup` loads `:subscription?` itself, so whether the card is saved doesn't depend on what the caller loaded.
- [x] **Translated sizes in admin.** `Admin.SubscriptionsLive` shows the size with `variant_size_label/1`, which is translated, and drops the redundant nil guard.
- [x] **One Stripe call on the card page.** It saves the card only when connected, so a visit doesn't call Stripe twice.
- [x] **No card on a cancelled subscription.** `:replace_card` refuses it, like `:change`. The webhook still returns `:ok` for that case, so Stripe doesn't keep retrying.

### Ash consistency

- [x] **Run as the system actor.** `Order :create_occurrence` and `Subscription :activate`, or its trigger replacement, get code interfaces and a place in the system bypass, and are called with `actor: system_actor()`. Do the same for the other `authorize?: false` calls in the subscription code, using existing interfaces such as `get_subscription`, or `get_by` the `unique_occurrence` identity for `find_occurrence`. A read that must stay unauthorised gets a one-line reason.
- [x] **Specific errors on the product page.** It shows the translated message from the returned `Ash.Error.Invalid`, not one fixed subscription message.
- [x] **One "skipped?" calculation.** "Is the next delivery skipped?" becomes a single calculation on Subscription, used by both the account and admin pages.
- [x] **Validations, not changes.** The subscribable check in `PopulateFromVariant` moves into a validation on `add_to_cart`.

### Trims

- ~~Drop `Subscription.card_message`~~: **kept**, by the user's decision. The column stays and the set-up email keeps reading it.
- [x] **Drop `stripe_id/1`** in `Payments`, and read `customer`/`payment_method` directly. Nothing expands them. Update the test fakes if needed.
- [x] **Drop the always-true conditions** in the `send_payment_failed_email` trigger's `where`: `origin == :subscription` and `not is_nil(customer_email)`.
- [x] **One subscription-line lookup in `ActivateSubscription`.** Find the subscription line once instead of loading `:subscription?` as well.
- [x] **One expression in `SubscriptionDelivery.subscription?/1`**, not two clauses.
- ~~Drop the duplicate interval test~~: **kept** (2026-10-09). The two tests aren't duplicates: `subscription_test.exs` checks the interval on the cart line at subscribe time, while `change_subscription_test.exs` checks `Subscription :change`'s own `attribute_in(:interval_weeks, ...)` validation. Dropping it would leave that validation untested.

### Alerting

- [x] **Confirm a failing occurrence job alerts.** Check that an occurrence job which keeps failing (an AshOban job returning an error, not raising) reaches ErrorTracker, and so the error-alert email. If it doesn't, make it, e.g. with `Logger.error` in the failing path or an `on_error` handler. Record what you found in the comments.

### Checks

- [x] New strings translated into sv and fi; CONTEXT.md and ADR 0003 updated if anything they say changes.
- [x] `mix format --check-formatted`, `mix compile --warnings-as-errors --force`, `mix ash.codegen --check` and the full `mix test` pass, with tests for each bug fix.

## Blocked by

- `08-card-with-first-delivery-only.md`

## Comments

**Bugs**

- Paid order always placed: `ActivateSubscription` left `finalize_checkout`. `finalize_checkout` now only stores the PaymentIntent's `customer` and `payment_method` on the order (new `orders.stripe_customer_id` / `stripe_payment_method_id`, migration `keep_subscription_card_on_order`), since the Subscription is no longer created while the PaymentIntent is at hand. The new Order trigger `:start_subscription` (every minute, `state == :placed and origin == :online and subscription? and is_nil(subscription_id)`) runs `Order :start_subscription`, which creates the Subscription through `Orders.activate_subscription` and links the order in one transaction. A failure fails the job, which retries; the order stays placed. The error-logging fallback in `ActivateSubscription` is gone. The set-up email is still queued once by `:activate`, and a re-run cancels because the order no longer matches. I used the cron alone, not `run_oban_trigger` from `finalize_checkout`, so not even a failed job insert can stop an order being placed; the set-up email can now arrive up to a minute after the receipt. Tests: the activation tests run the scheduler and worker; "a subscription that can't start leaves the paid order placed, and is tried again".
- One "today": new `Edenflowers.Expressions.HelsinkiToday`, an Ash custom expression `helsinki_today()` (registered in `config :ash, :custom_expressions`) whose `today/0` is also called from Elixir. It is evaluated when the query is built (checked), so expressions and Elixir use the same function. Used by the occurrence trigger's `where`, `changes_closed?`, `occur_unless_missed` and the new `Changes.StepToScheduledDate` (`days_from_today: 0` for `:reactivate`, `@lead_days + 1` for `:resume`). `first_open_day` keeps `DateTime.now!("Europe/Helsinki")`: it was already Helsinki, and `Availability.unavailable_reason/3` needs the time of day for the same-day deadline, so a date there would change behaviour. Test: `helsinki_today_test.exs` checks the date just after Helsinki midnight (a fixed instant passed in); the call sites can't be tested against the clock without faking time. Subscription tests now count dates from `HelsinkiToday.today()`, so they don't flake between 00:00 and 03:00 Helsinki.
- Concurrent changes: `CreateOccurrence.move_on` uses atomic updates: `next_fulfillment_date = date + interval_weeks * 7` from the row, and `array_remove(skipped_dates, date)` (passed as `{:atomic, expr}`, since Ash can't cast an array expression). Test: Jennie changes the interval during the Stripe call, and the next date uses the new one (fails on the old code).
- Stale id: the account page fetches with `Orders.get_subscription(id, actor: user)`. Test: pausing someone else's subscription flashes the error instead of crashing.
- `KeepSubscriptionAlone`: the read and each destroy return errors as changeset errors; notifications still pass through. No test: a read or destroy failure can't be provoked without faking the data layer.
- `Payments.setup` loads `subscription?` itself (system actor). The existing setup test now passes an order without it loaded (fails on the old code).
- Admin sizes use `variant_size_label/1`, nil guard dropped. Test with a Swedish session ("Stor").
- Card page: the static render no longer touches Stripe; saving and SetupIntents happen only when connected. Test: a SetupIntent that hasn't succeeded is retrieved once (was twice). The success test now follows the redirect, because the flash comes from the connected mount.
- `:replace_card` refuses a cancelled subscription. The webhook matches that error (`InvalidAttribute` on `:state`), logs a warning and returns `:ok`. Tests in `change_subscription_test.exs` and `stripe_handler_test.exs`.

**Ash consistency**

- System actor: new interfaces `Orders.activate_subscription`, `Orders.create_occurrence` and `Orders.get_occurrence` (`get_by_identity: :unique_occurrence`); `:activate`, `Order :create_occurrence` and `:start_subscription` are in the system bypasses. `find_occurrence`, `create_occurrence`, `ReactivateSubscription` (`get_subscription`) run as the system actor. Changes and validations pass on their own actor with `Ash.Context.to_opts(context)`: `ActivateSubscription`, the occurrence's line item, both email changes, `SubscriptionChangesOpen`, `SubscriptionDelivery`, `SubscriptionVariant` (now `Catalog.get_variant_by_id`) and `KeepSubscriptionAlone`. Aggregates are authorised, so the system actor saw no line items or payments on a placed order (`unpaid?` and `grand_total` came out wrong). `LineItem` and `Payment` gained a system read bypass, matching Order, Subscription and User. No unauthorised read is left in the subscription code.
- Product page: flashes the first message of the returned `Ash.Error.Invalid` (already translated, because `~t` runs in the LiveView's locale), otherwise "This couldn't be added to your cart.". `KeepSubscriptionAlone` now uses the full "A subscription is checked out on its own. Empty your cart to add this." message, which was already translated, so the usual case reads as before. Test: a forged subscription of an ordinary product shows "This product can't be subscribed to".
- `Subscription.next_delivery_skipped?` (`next_fulfillment_date in skipped_dates`), loaded by `:mine` and `:admin_list`, used by both pages.
- `Validations.Subscribable` on `add_to_cart` replaces the check in `PopulateFromVariant`.

**Trims**

- Skipped: dropping `Subscription.card_message`. The user decided to keep the column. No migration, no `first_order_has_card?`; the set-up email still reads the subscription's `card_message`.
- `stripe_id/1` dropped. The PaymentIntent is read with `Map.get(payment_intent, :customer)` / `:payment_method`, as before, because most test fakes have no such keys. The SetupIntent's `payment_method` is read directly. No fake needed changing.
- `send_payment_failed_email`'s `where` is `payment_link_open? and is_nil(details_emailed_at)`.
- `ActivateSubscription` loads `line_items` once and finds the subscription line. The trigger's `where` already guarantees there is one.
- `SubscriptionDelivery.subscription?/2` is one `Ash.load!(..., lazy?: true)`.
- Skipped: the "duplicate" interval test. It isn't a duplicate. `change_subscription_test.exs` checks `Subscription :change` refusing interval 3; `subscription_test.exs` checks the cart line (`LineItem :add_to_cart`). They are different actions with their own validations.

**Alerting**

- No change was needed. When the action returns an error, the AshOban worker raises it (`define_schedulers.ex`: `{:error, error} -> raise Ash.Error.to_error_class(error)`). `handle_error` then calls `Logger.error("Error occurred for ... on action: create_occurrence ...")` on every attempt (`log_final_error?` and `log_errors?` default to true, and there is no `on_error`) and reraises. Both reach ErrorTracker: the `Logger.error` comes from `Edenflowers.Orders.Workers.CreateOccurrence`, so `ErrorTrackerLogHandler` reports it, and the reraise emits `[:oban, :job, :exception]`, which ErrorTracker's Oban integration reports. A new or unresolved error sends the alert email. The same holds for `:start_subscription`.

**Checks**

- 1 new string ("This couldn't be added to your cart."), translated into sv and fi. The old "A subscription is checked out on its own" msgid was removed by the extract. CONTEXT.md and ADR 0003 don't describe when the Subscription is started, so they are unchanged.
- `mix format --check-formatted`, `mix compile --warnings-as-errors --force`, `mix ash.codegen --check` and `mix test` pass. The full suite ran twice: 933 tests, 0 failures each time.

**Open questions**

- An order whose Subscription can never start (for example, Stripe returned no payment method) keeps failing. The job is discarded after 20 attempts, and the scheduler then queues it again. ErrorTracker groups the repeats, but it keeps erroring until Jennie deals with it.
- `skip` and the admin's pause/resume are still read-modify-write. Only the occurrence job's writes were made atomic.
