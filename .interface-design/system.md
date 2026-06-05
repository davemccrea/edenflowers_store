# Admin Interface — Design System

Scope: the `/admin` back-office (LiveViews under `EdenflowersWeb.Admin.*`). The
customer storefront is a separate register (serif, romantic) and is **not**
governed by this file.

## Intent

- **Who:** the florist / shop owner, doing operational work — checking the day's
  orders, reviewing AI-extracted expenses, editing fulfillment availability.
- **Job:** verify and act, fast. Read a number, trust it or fix it, move on.
- **Feel:** calm, warm, operational. The storefront's world (cream paper, forest
  stems) carried into a denser, sans-serif back-office register.

## Foundations

- **Framework:** DaisyUI utilities on Tailwind. Prefer DaisyUI tokens
  (`base-100/200/300`, `base-content`, `primary`, semantic `warning/error/success`)
  over raw hex. See [[feedback-daisyui-components]].
- **Palette:** warm neutral spine at hue ~75 (`base-*` defined in
  `assets/css/app.css`), primary = muted forest green
  `oklch(0.3684 0.0478 156.76)`. Color means something — primary marks
  "today"/active/links; `warning` marks low-confidence/needs-attention. No
  decorative color.
- **Typography:** body is `font-sans` (Open Sans) — deliberately NOT the
  storefront's `font-serif`. Reuse the shared `eyebrow` utility (uppercase,
  `tracking-[0.18em]`) for section labels and `logo-wordmark` for the brand.
  Numbers that get verified use `font-mono tabular-nums`.

## Depth strategy: borders-only

Dense tool → flat. Separate regions with low-opacity borders
(`border-base-300/70`), never drop shadows. Raised surfaces (widget cards) sit on
the `base-100` canvas at `base-100` + a border — equal lightness, not darker.
Inputs are the only inset surface (DaisyUI `input-bordered` handles this).

## Spacing

Base unit 4px (Tailwind scale). Conventions in use:
- Page padding: `px-8 py-8` (owned by `<.admin_page>` — don't set per-page).
- Card/widget padding: `p-5`.
- Header-to-content gap: `mb-8` (owned by `admin_page_header`).
- Inter-card grid gap: `gap-5`.
- List rows: `space-y-1.5` (tight) or `divide-y ... py-2` (with separators).

## Border radius

`rounded-lg` for cards/widgets, DaisyUI defaults for controls/badges. No large
radius on small elements.

## Page width is a semantic choice

Use `<.admin_page width=...>` — never hand-roll `max-w-*`:
- `wide` (`max-w-4xl`) — dashboards, calendars, multi-column.
- `narrow` (`max-w-2xl`) — single-record detail/edit.
- `full` — data tables that use the whole canvas.

## Component patterns (`EdenflowersWeb.Admin.Components`)

- **`<.admin_page width>`** — page shell; owns padding + max-width.
- **`<.admin_page_header title back back_label>`** with `<:subtitle>` and
  `<:actions>` slots. Use `<:subtitle>` for supporting copy — do NOT add a
  sibling `<p>` with negative margin.
- **`<.widget title count>`** — dashboard card surface. Owns the frame so every
  widget agrees on border/radius/padding; the **content differs per widget's
  job** (Upcoming Orders = prep-ledger; Unreviewed Expenses = triage queue with
  amount column). Two widgets must never share the same internal layout.
- **`<.count_badge count active>`** — pill; `primary/10` when active, muted when 0.
- **`<.confidence_badge confidence>`** — shared by the expenses table and detail
  view. low→error, medium→warning, high→success.
- **`<.payment_status_badge status>` / `<.fulfillment_status_badge status>`** —
  order status pills (paid/fulfilled→success, failed→error, refunded→warning,
  pending→ghost). These ARE word-badges in a column — the exception to the
  "status columns are glyphs" rule below, because an order's payment/fulfillment
  state is a value the operator filters on, not a binary done/not-done glance.

### Dashboard widget signatures (don't converge them)

- **Upcoming Orders = a prep-ledger.** A florist preps to the fulfillment day, so
  date is the organising axis: each day is a row-group under an `eyebrow` header.
  **Today** is the signature — a `bg-primary/5 ring-1 ring-primary/15` tinted band
  given presence; days ahead are plain `divide-y` rows. Rows are full-width
  (`grid` that collapses `[1fr_auto]`→4-track at `sm:`) so a one-order day wastes
  no horizontal space. NOT a card grid (sparse days leave dead space) and NOT
  ungrouped (date is the floral worklist's spine). Gift orders carry an accent
  badge with the recipient; a trailing pencil inside that badge = "card to write"
  (presence only — never the message text).

## Data tables (Cinder)

Use `theme={EdenflowersWeb.Admin.CinderTheme}` — NOT the raw `"daisy_ui"`
string. The custom theme `extends :daisy_ui` and only remaps the filter-panel
header, because the storefront redefines DaisyUI's `card-title` as a large serif
heading (`assets/css/app.css`) and the admin must not inherit it. If another
Cinder class collides with a storefront utility, override it there too — never
edit the global utility.

**Status columns are glyphs, not labels.** A column read top-to-bottom is a
scan: use ✓ (`hero-check`, `text-success`) / muted `—` (`text-base-content/30`,
`aria-hidden`), with an `sr-only` label on the positive state. Don't repeat a
word-badge down a column, and don't place a status pill adjacent to another pill
column (e.g. Confidence) — they read as a false group.

## Dates, times, money — always via Localize

Never hand-roll `Calendar.strftime` or `"#{amount} #{currency}"`. Route every
date, datetime, and money value through `Edenflowers.Localize.Format` (CLDR),
the same path the receipt and email use:

- `Format.date(date, locale)` — CLDR short date.
- `Format.datetime(dt, locale)` — shifts UTC → `Europe/Helsinki`, CLDR short.
- `Format.amount(value, currency, locale)` — accepts the lowercase expense
  currency atoms (`:eur`/`:sek`), upcases to ISO for CLDR.

Resolve the locale once in `mount` with `Localize.get_locale()` and assign it.
Bare `:date` attributes carry no timezone — format them, but never shift them.
Only `:utc_datetime` values get the Helsinki shift.

## Forms

Admin forms use **medium (DaisyUI default) controls** for density — the operator
wants the whole record visible, not storefront-sized inputs. Set every control
explicitly so the form is internally consistent: `class="input w-full"`,
`class="select w-full"`, `class="textarea w-full"`.

Watch the `core_components.input` defaults: text inputs default to `input-lg`
but selects/textareas to medium. So "just omit `class`" produces a *mismatched*
form (tall text inputs, shorter selects). Always pass the explicit medium class
on admin forms rather than relying on the per-type default.

The detail-page hero `total_amount` may duplicate the form's amount field —
that one duplication is fine (read-anchor vs. editor); don't render any *other*
field twice. The form is the display for editable data.

## Information hierarchy

Lead with the fact the human is verifying. On the expense detail page the
**amount** + **confidence** are a hero band above the metadata grid — metadata
(VAT number, document id, timestamps) is demoted to `text-sm` `dl` rows.

## Text hierarchy (use all four)

`base-content` (primary) · `/55` (secondary) · `/45` (metadata labels) ·
`/35–/40` (muted/empty-state). Don't flatten to two levels.
