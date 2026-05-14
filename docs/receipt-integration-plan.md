# Receipt PDF integration plan

Wires the Typst template from #193 into the order confirmation email.

Previously blocked on #158 (immutable-orders ADR); the implementation
of that ADR landed in #201, and #198 collapsed `Email.order_confirmation/1`
into a thin envelope builder. Both upstream dependencies are now in main.
See the "Snapshot field map" section for the concrete fields the JSON
payload should read.

## Pieces to add

1. **`Edenflowers.Receipt`** — single public `generate/1` taking a loaded
   order. Marshals to the JSON shape in `priv/receipts/sample/order.*.json`
   (all values pre-formatted strings; `lang` from `order.locale`). Shells
   out:

   ```
   typst compile priv/receipts/main.typ - \
     --input order=<json> \
     --font-path priv/receipts/fonts
   ```

   Returns `{:ok, pdf_binary}` from stdout, `{:error, reason}` on non-zero
   exit. No tempfiles.

2. **Hook into `Email.order_confirmation/1`** (`lib/edenflowers/email.ex`).
   Already a thin envelope builder after #198; pipe the result through
   `Swoosh.Email.attachment/2` with filename
   `eden-flowers-#{order.order_reference}.pdf`. Single call site, no worker
   changes — `SendOrderConfirmationEmail` already loads every aggregate
   the payload needs (and after #201 it can drop the `:promotion` and
   `fulfillment_option: [:tax_rate]` loads in favour of the snapshot
   columns).

3. **Formatting helpers** — per-line `unit_price_ex_vat` derives from
   `unit_price` and `tax_rate`; currency and dates use the existing CLDR
   helpers already living in `Edenflowers.Email` (`format_currency/2`,
   `format_date/2`, `format_datetime/2`). Move them to a shared module
   (e.g. `Edenflowers.Localize.Format`) so both `Email` and `Receipt`
   call the same helpers and the Typst side stays locale-agnostic.

## JSON payload shape (post-#201)

The receipt JSON keys mirror the Ash attribute names 1:1 — flat
structure, no editorial grouping. The Typst template reads each key
directly. No live joins to `Promotion` or `FulfillmentOption` are
needed; every value comes from the placed `Order` (snapshot columns,
aggregates, and calculations) or its `LineItem`s.

Order-level keys:

| JSON key                  | Source on `Order`                            |
| ------------------------- | -------------------------------------------- |
| `lang`                    | `locale` (first two chars: `sv-FI` → `sv`)   |
| `order_reference`         | `order_reference`                            |
| `ordered_at`              | `ordered_at` (formatted via CLDR)            |
| `customer_name`           | `customer_name`                              |
| `customer_email`          | `customer_email`                             |
| `fulfillment_method`      | `fulfillment_method` (snapshot)              |
| `recipient_name`          | `recipient_name`                             |
| `recipient_phone_number`  | `recipient_phone_number`                     |
| `delivery_address`        | `geocoded_address \|\| delivery_address`     |
| `delivery_instructions`   | `delivery_instructions`                      |
| `fulfillment_date`        | `fulfillment_date` (formatted)               |
| `card_message`            | `card_message`                               |
| `fulfillment_amount`      | `fulfillment_amount` (formatted currency)    |
| `discount_amount`         | `discount_amount` aggregate (formatted)      |
| `tax_amount`              | `tax_amount` calc (formatted)                |
| `line_total`              | `line_total` aggregate (formatted) — order's "subtotal" |
| `total`                   | `total` calc (formatted) — grand total       |

Per-line keys (under `line_items[]`), sourced from `LineItem`:

| JSON key             | Source on `LineItem`                                  |
| -------------------- | ----------------------------------------------------- |
| `product_name`       | `product_name`                                        |
| `variant_size`       | `variant_size`                                        |
| `quantity`           | `quantity`                                            |
| `unit_price`         | `unit_price` (formatted currency)                     |
| `unit_price_ex_tax`  | derived: `unit_price / (1 + tax_rate)` (formatted)    |
| `tax_rate`           | `tax_rate` (formatted percentage)                     |
| `line_total`         | `line_total` calc (formatted)                         |

Snapshots store **raw decimals**, not pre-formatted strings — `Receipt`
formats at render time using the shared CLDR helpers. The Typst template
treats every value as a string, so the order-level `line_total` and the
per-line `line_total` never collide (they live at different nesting levels).

## Deployment

- Add `typst` to the runtime image (`Dockerfile`).
- Fonts are already committed under `priv/receipts/fonts/` (#194-era
  vendoring) and shipped via the standard `COPY priv priv` step, so
  no extra build action is needed.

## Persistence

Render once at placement and write the PDF to disk; never regenerate.
The deploy target is bare metal, so a local folder is the simplest
durable option — no object storage needed.

- **Path** — configurable, defaulting to e.g.
  `/var/lib/edenflowers/receipts/`. Outside the release directory so
  deploys don't wipe or shadow it.
- **Layout** — shard by year/month: `2026/05/EF-2026-00428.pdf`.
  Avoids one giant flat directory, easier to prune.
- **Write-once** — never overwrite. The file is the canonical artifact
  that was emailed; matches the #158/#201 immutability story.
- **Serving** — through a Phoenix controller that re-authorises against
  the order, not via static file serving. Otherwise anyone who guesses
  an `EF-2026-…` reference downloads someone else's receipt.
- **Backups** — the receipts folder must be in the backup scope
  alongside Postgres. Call this out in the deploy runbook.

Keeps the email attachment, the customer-support reprint, and the VAT
audit trail all reading from the same on-disk file.

## Tests

- `Edenflowers.ReceiptTest` — golden test: marshal a fixture order, diff
  the JSON against `priv/receipts/sample/order.en.json`. Skip the
  `typst` shell-out in CI unless the binary is present.
- Extend `checkout_happy_path_test.exs` to assert the delivered email
  carries one PDF attachment with the expected filename.

## Resolved open questions

- **Snapshot coverage** — see the field map above. Every value the
  payload needs is on the placed `Order` or its `line_items`, with no
  live joins required.
- **Formatting** — snapshots are raw decimals; the receipt module
  formats at render time. Share the CLDR helpers currently in
  `Edenflowers.Email` between `Email` and `Receipt` rather than
  duplicating them.

## Still open

- **Tax rate per line vs. order-level VAT breakdown.** The Typst
  template renders one `vat_rate` per line and a single `tax` total;
  this works as long as every line carries the same rate (today: yes —
  one Finnish flower-product rate). If we ever sell mixed-rate items,
  the JSON payload (and template) need a per-rate breakdown.
- **Receipt locale vs. customer's current locale.** Today
  `order.locale` is captured at checkout and persists through
  `:placed`. The receipt uses it directly; no follow-up needed unless
  we decide receipts should be re-rendered when a customer changes
  language post-purchase (probably not — the emailed PDF is the
  archival artifact).
- **Where should the shop's identity (name, address, business ID,
  IBAN) come from?** Tracked separately in #195 — `priv/receipts/shop.toml`
  works for self-contained Typst previews but duplicates the address
  hardcoded into the order-confirmation email template. Acceptable to
  leave duplicated for now; revisit if the address changes.
