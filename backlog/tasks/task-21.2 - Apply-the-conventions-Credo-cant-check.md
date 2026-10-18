---
id: TASK-21.2
title: Apply the conventions Credo can't check
status: ready-for-agent
assignee: []
created_date: '2026-10-18 04:05'
labels: []
dependencies:
  - TASK-21.1
parent_task_id: TASK-21
type: refactor
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

`TASK-21` decision 2, for what no Credo check covers:

1. **Ash DSL names.** In every resource, alias `Changes`, `Validations`, `Calculations` and `Actions` (own domain and others') and use the short names in `change`/`validate`/`calculate` lines. Worst offenders:
   - `lib/edenflowers/orders/order.ex`: the `Edenflowers.Payments.Changes.*` and `Edenflowers.Payments.Validations.*` references. Relationship targets (e.g. `:1030`, `:1033`) stay in full, as everywhere else.
   - `lib/edenflowers/orders/subscription.ex`: every `Edenflowers.Orders.Changes.*` / `Validations.*`.
   - `lib/edenflowers/courses/course_registration.ex`: `Edenflowers.Courses.Validations.MatchesPaymentAmount` and the `Edenflowers.Payments.*` references.
   - `user.ex`, `product.ex`, `line_item.ex`, `fulfillment_option.ex`.
2. **Inline enums** referenced as `__MODULE__.Name` (`fulfillment_option.ex`, `expense.ex`).
3. **`@impl true`** on every callback in the customer-facing LiveViews (`features/{marketing,store,courses,checkout,account,auth}/`), the LiveComponents (`components/cart/*`, `components/date_picker.ex`, `components/newsletter_signup.ex`) and the hand-written Oban workers (`orders/workers/`, `accounts/workers/`, `pricing/workers/`, `error_alerts/`, `wedding_enquiry/send_emails.ex`).
4. **LiveView order**: `mount`, `handle_params`, `render`, `handle_event`/`handle_info`/`handle_async`, then components and helpers. Move `render` in the 13 LiveViews that put it after the handlers (e.g. `admin/dashboard_live.ex`, `admin/order_form_live.ex`, `checkout/pay_live.ex`, `marketing/weddings_live.ex`), and the helper defined before `mount` in `checkout/checkout_live.ex` and `admin/promotions_live.ex`.
5. **Module attributes after the directives**: `@default_view` in `admin/orders_live.ex`, `admin/promotions_live.ex`, `admin/subscriptions_live.ex`, and the mid-module ones in `checkout/checkout_live.ex`, `external/claude_api.ex`, `payments/changes/record_payment.ex`, `components/core_components.ex`, `components/date_picker.ex`, unless an attribute is deliberately kept next to the only function that uses it (say so in a comment, then).
6. **`system_actor()`** short where the module imports `Edenflowers.Actors`; add the import where a module writes it in full more than once.

Split into several commits by item so each diff is reviewable; moving functions makes `git diff` noisy, so keep moves and edits in separate commits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each item above holds across `lib/`
- [ ] #2 `mix precommit` passes
- [ ] #3 No behaviour change; the existing suite passes
<!-- AC:END -->
