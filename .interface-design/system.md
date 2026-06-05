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
  job** (Open Orders = timeline/agenda; Unreviewed Expenses = triage queue with
  amount column). Two widgets must never share the same internal layout.
- **`<.count_badge count active>`** — pill; `primary/10` when active, muted when 0.
- **`<.confidence_badge confidence>`** — shared by the expenses table and detail
  view. low→error, medium→warning, high→success.

## Information hierarchy

Lead with the fact the human is verifying. On the expense detail page the
**amount** + **confidence** are a hero band above the metadata grid — metadata
(VAT number, document id, timestamps) is demoted to `text-sm` `dl` rows.

## Text hierarchy (use all four)

`base-content` (primary) · `/55` (secondary) · `/45` (metadata labels) ·
`/35–/40` (muted/empty-state). Don't flatten to two levels.
