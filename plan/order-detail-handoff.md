# Handoff: Admin order detail page (`/admin/orders/:id`)

## Goal
Expand the admin dashboard so a row in the orders table opens a full order detail
page at `/admin/orders/:id`, including a guarded "mark as fulfilled" action.

Branch: `admin-dashboard-redesign`. This is a `frontend-design` build task that was
stress-tested via `grill-me` first — all design decisions below are **resolved with
the user**, not open questions.

## Status: NO code applied yet
The grilling is complete; implementation had just started. One edit to
`lib/edenflowers/store/order.ex` (adding `code_interface` defines) **failed** because
the file was modified externally — nothing landed. Treat the codebase as untouched by
this feature. Start fresh from the spec below.

## Resolved decisions (from the grill)
1. **Page purpose** — view **+ actions** (not read-only).
2. **Actions this PR** — **only** "mark as fulfilled". No resend-receipt, no refund.
3. **Fulfill semantics** — **forward-only + confirm dialog**. Irreversible; the user
   noted it will later fire emails to sender/recipient, so the `mark_fulfilled` action
   is the single seam where those side-effects hook in later. Confirm copy must name
   the irreversibility. No "unfulfill" path.
4. **URL identifier** — UUID `:id` (`/admin/orders/:id`), matching `/admin/expenses/:id`.
5. **Navigation** — whole-row click via Cinder's `click` attr (auto cursor-pointer).
6. **Content** — everything: customer + fulfillment + read-only line items + money
   breakdown, payment/Stripe details, receipt status, timeline/metadata.
7. **Design lean** — match the existing admin language (NOT a bold new aesthetic).
   Reuse `admin_page`, `admin_page_header`, eyebrow/hero/system-facts patterns and the
   existing badges. "Distinctive" here = precise + well-composed.
8. **Layout** — two-column on `width="wide"`, stacks on mobile.
9. **Stripe** — link `payment_intent_id` to the Stripe dashboard; derive test/live mode
   from the publishable key prefix (`pk_test_` → `/test/payments/...`, else `/payments/...`).
10. **Tests** — LiveView tests (render, mark_fulfilled flips status + shows Fulfilled
    badge, not-found redirect) **and** policy tests (admin can mark_fulfilled past the
    placed-order seal; non-admins and other updates still blocked).

## Implementation plan

### 1. `lib/edenflowers/store/order.ex`
- `code_interface`: add
  `define :get_for_admin, action: :admin_show, args: [:id]` and
  `define :mark_fulfilled, action: :mark_fulfilled`.
- New read action `:admin_show` — `argument :id, :uuid`, `get? true`,
  `filter expr(id == ^arg(:id) and state == :placed)`, and a `prepare build(load: ...)`
  loading line_items (+ their `:subtotal`) and the order calcs/aggregates needed for the
  totals breakdown: `:customer_name, :grand_total, :items_subtotal, :items_tax, :tax,
  :fulfillment_tax, :discount, :distance_km, :promotion, :fulfillment_option`.
  Consider a module attr `@admin_show_load` mirroring `@checkout_load`. Keep separate
  from `:admin_list` (the codebase deliberately splits table vs detail loads).
- New update action `:mark_fulfilled` — forward-only:
  `validate attribute_equals(:fulfillment_status, :pending)` +
  `change set_attribute(:fulfillment_status, :fulfilled)`. Mirror `mark_payment_failed`
  (no `require_atomic? false` needed; comparison is to a non-nil value).
- **Policy** — extend the existing **admin bypass** (currently only
  `authorize_if action_type(:read)`) with `authorize_if action(:mark_fulfilled)`.
  This is the security boundary: admins clear the `forbid_if state == :placed` seal
  **only** for this one action; every other update stays sealed. Mirrors the scoped
  system-bypass pattern already in the file.

### 2. `lib/edenflowers/stripe_api.ex`
- Add a plain public helper (not part of the behaviour), e.g.
  `dashboard_payment_url(payment_intent_id)`, deriving mode from
  `Application.get_env(:edenflowers, :stripe_publishable_key)` — `pk_live_*` → live,
  anything else (incl. nil in test) → test mode.

### 3. `lib/edenflowers_web/live/admin/order_detail_live.ex` (new)
- Model closely on `lib/edenflowers_web/live/admin/expense_detail_live.ex`.
- `mount(%{"id" => id}, ...)`: `Order.get_for_admin(id, actor: current_user)`; on
  `{:ok, %Order{} = order}` assign + locale; otherwise flash + `push_navigate` to
  `~p"/admin/orders"`. (`get? true` may return `{:ok, nil}` for missing — catch it.)
- `admin_page width="wide"`, `admin_page_header` with `back={~p"/admin/orders"}`,
  `back_label="Orders"`, `title={order.order_reference}`.
  - `:actions` slot: if `fulfillment_status == :pending`, a `btn btn-primary btn-sm`
    "Mark as fulfilled" with `data-confirm` naming irreversibility; if `:fulfilled`,
    a success badge (copy the expense "Reviewed" badge pattern).
  - Hero: grand total (big tabular-nums number) + `payment_status_badge` /
    `fulfillment_status_badge`.
  - Two-column grid: **main** = read-only line items + money breakdown
    (subtotal, discount/promotion, tax, fulfillment fee, grand total);
    **aside** = customer (name, mailto email), fulfillment (method, option, date,
    recipient name/phone, delivery address/instructions, distance, gift + card message),
    payment (Stripe-linked payment_intent_id + status), receipt status
    (`receipt_emailed_at`), metadata strip (`ordered_at`, locale, `order_reference`).
- **Read-only line items**: `LineItemsComponent` is edit-coupled (increment/decrement/
  remove wired to checkout) and **cannot** be reused. Write a small private read-only
  function component (image, name, variant_size, quantity, `Edenflowers.Format.money(subtotal)`).
- `handle_event("mark_fulfilled", ...)` → `Order.mark_fulfilled(order, actor: current_user)`,
  reassign + flash.

### 4. `lib/edenflowers_web/router.ex`
- Add `live "/orders/:id", EdenflowersWeb.Admin.OrderDetailLive` immediately after the
  `/orders` route in the `:admin_routes` live session (line ~87).

### 5. `lib/edenflowers_web/live/admin/orders_live.ex`
- Add to the `Cinder.collection`:
  `click={fn order -> JS.navigate(~p"/admin/orders/#{order.id}") end}`.

### 6. Tests
- New `test/edenflowers_web/live/admin/order_detail_live_test.exs` — model on
  `test/edenflowers_web/live/admin/fulfillment_calendar_live_test.exs`.
- Policy tests for `mark_fulfilled` (admin allowed past seal; non-admin/other updates
  blocked) — co-locate with existing Order resource tests if present.

## Key facts already verified (don't re-discover)
- `Cinder.collection` accepts `click` (fn item -> JS); table layout maps it to a row
  `phx-click` and adds `cursor-pointer`. Source: `deps/cinder/lib/cinder/collection.ex`,
  `deps/cinder/lib/cinder/renderers/table.ex`.
- Admin reads already authorized via the admin bypass; `forbid_if state == :placed`
  only blocks updates.
- `Edenflowers.Format`: `money/1`, `currency/2`, `date/2`, `datetime/3`, `percentage/2`.
  `datetime/3` calls `DateTime.shift_zone!` — will crash on nil (placed orders always
  have `ordered_at`, so fine).
- `LineItem` fields: `quantity, unit_price, product_name, product_image_slug, is_card,
  variant_size`; calcs `subtotal, total, discount, tax`; belongs_to `product` (→ `product_id`).
- Admin component helpers in `lib/edenflowers_web/components/admin/components.ex`:
  `admin_page`, `admin_page_header` (back/back_label/subtitle/actions slots),
  `payment_status_badge`, `fulfillment_status_badge`, `widget`. Width classes:
  wide=max-w-4xl, narrow=max-w-2xl, full=none.
- Stripe config in `config/runtime.exs` (~line 44): `:stripity_stripe api_key` (secret),
  `:edenflowers, :stripe_publishable_key`.
- Project: run `source .env` before `mix`. Coding standards in `CLAUDE.md` — no comments
  restating code; only non-obvious intent.

## Suggested skills for the next session
- `frontend-design:frontend-design` — the originating skill; keep its aesthetic guidance
  in mind but honor decision #7 (match existing admin language, not a bold new look).
- `phoenix-framework` and `ash-framework` — for the LiveView, the new Ash read/update
  actions, and especially the policy bypass carve-out.
- `tdd` — decision #10 wants LiveView + policy tests; the policy carve-out is a security
  boundary worth driving test-first.
- `gettext-sigils-localization` — user-facing strings (flash messages, button/confirm
  copy) should follow the project's i18n conventions if applicable to admin views.
