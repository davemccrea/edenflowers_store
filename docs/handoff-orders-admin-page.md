# Handoff — Orders admin page + dashboard rework

## Task

Build two things, in this order:

1. **Orders admin page** at `/admin/orders` — a read-only Cinder **table** of placed orders.
2. **Dashboard "Upcoming Orders" rework** — replace the timeline widget with a **card grid**, keeping the existing date grouping; promote it to full width.

Both were fully designed in a `/grill-me` session. The decision tree is **fully resolved** — no open product questions remain. What's left is implementation plus a couple of Cinder-syntax confirmations (noted below).

## State

- Branch: `admin-dashboard-redesign`. Working tree was clean at session start; **no code written yet** — this is design-complete, implementation-pending.
- Reference implementation to mirror: `lib/edenflowers_web/live/admin/expenses_live.ex` (Cinder collection + `CinderTheme` + `actor` + `.admin_page` shell).

## Deliverable 1 — Orders page (`/admin/orders`)

**New read action** on `Edenflowers.Store.Order` (`lib/edenflowers/store/order.ex`) — call it `:admin_list`:
- Filter `state == :placed` (placed orders only — no in-progress/abandoned checkout carts).
- Default sort `ordered_at: :desc` (newest first).
- Loads: `customer_name`, `order_reference`, `fulfillment_date`, `fulfillment_method`, `grand_total`, `payment_status`, `fulfillment_status`.
- Do **not** reuse `:open` or `:completed` — those serve the dashboard/domain split and shouldn't be overloaded with table loads.

**New LiveView** `EdenflowersWeb.Admin.OrdersLive` at `lib/edenflowers_web/live/admin/orders_live.ex` — mirror `ExpensesLive` exactly:
- `Layouts.admin` → `.admin_page width="full"` → `.admin_page_header title="Orders"` → `Cinder.collection`.
- `actor={@current_user}`, `theme={EdenflowersWeb.Admin.CinderTheme}`, point at the `:admin_list` action.
- **No** `click` handler — rows are not clickable (no admin order detail page this round; deliberately deferred).
- Columns:

  | Column | Field | sort | filter |
  |---|---|---|---|
  | Order reference | `order_reference` | — | — |
  | Customer | `customer_name` | — | — |
  | Date | `ordered_at` | ✓ (default desc) | — |
  | Fulfillment date | `fulfillment_date` | ✓ | — |
  | Method | `fulfillment_method` | — | ✓ |
  | Total | `grand_total` | — | — (display-only; **no sort** — avoids calc-sort pushdown risk) |
  | Payment | `payment_status` | — | ✓ |
  | Fulfillment | `fulfillment_status` | — | ✓ |

- Reuse `Edenflowers.Localize.Format` (`Format.date`, `Format.amount`) and the dashboard's `fulfillment_icon`/`fulfillment_label` pattern for the method cell.

**Route**: add `live "/orders", EdenflowersWeb.Admin.OrdersLive` to the `:admin_routes` live_session in `lib/edenflowers_web/router.ex` (~line 86–90).

**Nav**: add `{"/admin/orders", "Orders", true, "hero-shopping-bag"}` to the nav list in `lib/edenflowers_web/components/layouts.ex` (~line 146–148), placed sensibly among Dashboard / Expenses / Calendar.

## Deliverable 2 — Dashboard "Upcoming Orders" rework

File: `lib/edenflowers_web/live/admin/dashboard_live.ex`.

**What's wrong today** (per user): the layout — it's a timeline (`<ol>` left-rule agenda, `orders_widget/1` ~line 66–103), they want **cards**, and **richer information**. Scope (multi-day "upcoming", today highlighted) is **correct and must be kept** — do not narrow to today-only. Engine stays hand-rolled HEEx, **not Cinder** (Cinder grid can't do the date-grouped sections this widget needs).

**Changes:**
- Replace the timeline rows with a **card grid**, keeping the existing `Enum.group_by(& &1.fulfillment_date)` grouping and the `Today / Tomorrow / Weekday` headers (today highlighted in primary). See `format_order_date/2`.
- **Layout**: promote "Upcoming Orders" to **full-width on its own row**; the Expenses widget stacks **full-width below** it (currently they share a 2-col grid at `dashboard_live.ex:49`). So: two stacked full-width rows.
- **Card content — six fields** (current card shows only customer name + method icon + reference):
  - customer name
  - order reference
  - fulfillment method as a **labelled badge** (icon + label, not icon-only)
  - grand total (€)
  - line-item count using the **`non_card_line_item_count`** aggregate (products only — excludes the greeting-card line item)
  - gift indicator: gift badge + `recipient_name`, **plus** a small "card to write" indicator when `card_message` is present (render presence only, not the message text). For non-gift orders `recipient_name` is nil — fall back / omit, don't render blank.
- **Widen the `:open` action's `load:`** (in `order.ex`, currently `[:customer_name, :order_reference, :fulfillment_date, :fulfillment_option_name, :fulfillment_method]`) to add: `grand_total`, `non_card_line_item_count`, `gift`, `recipient_name`, `card_message`.

## Confirmations to make while building (not decisions — just verify against Cinder 0.14)

- Exact syntax for default sort: column-level `sort` direction vs. a collection-level default-sort attribute.
- The filter type Cinder infers for atom `one_of` attributes (`fulfillment_method`, `payment_status`, `fulfillment_status`) — expect select/enum filters; confirm prompts/labels render correctly.
- Cinder layouts available (confirmed from docs): `table` (default), `:list`, `:grid` — all share filter/sort/search/pagination. We use the default table for the Orders page.

## Policy / data facts already verified (don't re-investigate)

- `Order` has `bypass actor_attribute_equals(:admin, true) do authorize_if action_type(:read) end` — admin reads are authorized.
- `LineItem` (`lib/edenflowers/store/line_item.ex:45–46`) has the **same** admin read bypass — so `grand_total` and `non_card_line_item_count` (which cross into the `line_items` aggregate) load cleanly for an admin actor. No runtime policy surprise expected.
- `non_card_line_item_count` aggregate already exists on `Order` (filters `is_card == false`).
- `gift` (bool), `recipient_name` (string), `card_message` (string) are plain attributes already on `Order` — cheap to load.
- Dashboard loads orders in `mount/1` via `Order.get_all_open!(actor: actor)` — every card field must be in the `:open` action's `load:`.

## Build order & verification

1. `:admin_list` read action.
2. `OrdersLive` + route + nav.
3. Dashboard rework (widen `:open` load, card grid, full-width layout).

Run `mix` checks along the way. **Remember: `source .env` before running mix** (per CLAUDE.md). Verify rendering in the running app (placed-order seed data exists — see recent commit `5f847be`).

## Suggested skills for the next session

- **`ash-framework`** — for writing the `:admin_list` read action correctly (filter/sort/load, action design idioms).
- **`phoenix-framework`** — for the LiveView + route wiring.
- **context7 / `context7-mcp`** — to confirm Cinder 0.14 syntax (default sort, filter inference for atom enums). Per the user's global rule, prefer Context7 over web search for library docs.
- **`verify`** or **`run`** — to launch the app and confirm the Orders table and the new dashboard cards render against seeded data before wrapping up.
- **`gettext-sigils-localization`** — any new user-facing strings (column labels, badges, empty states) should follow the project's GettextSigils convention.

## Notes / preferences observed

- User favours DaisyUI utilities and extracting repeated patterns into components (see auto-memory `feedback_daisyui_components.md`).
- Coding standards (CLAUDE.md): no comments restating what code does; comment only non-obvious intent; no dead/commented-out code; readability over blind DRY.
