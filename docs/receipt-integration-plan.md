# Receipt PDF integration plan

Wires the Typst template from #193 into the order confirmation email.

**Blocked on #158** (immutable orders ADR). Receipts are the canonical
snapshot of a placed order; the JSON payload should read from snapshot
fields, not live joins through `:line_items` / `:promotion` / aggregates.
Building against today's shape means rewriting the mapping when
snapshots land.

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
   After #198 lands this is a thin envelope builder; pipe the result
   through `Swoosh.Email.attachment/2` with filename
   `eden-flowers-#{order.reference}.pdf`. Single call site, no worker
   changes — `SendOrderConfirmationEmail` already loads every aggregate
   the payload needs.

3. **Formatting helpers** — per-line `unit_price_ex_vat` derives from
   `unit_price` and `tax_rate`; currency and dates use the existing CLDR
   helpers. Keep formatting in one private module so the Typst side stays
   locale-agnostic.

## Deployment

- Add `typst` to the runtime image (`Dockerfile`).
- `priv/receipts/fonts/` is gitignored — vendor the static weights or
  run `fetch_fonts.sh` during image build so they're present at runtime.

## Tests

- `Edenflowers.ReceiptTest` — golden test: marshal a fixture order, diff
  the JSON against `priv/receipts/sample/order.en.json`. Skip the
  `typst` shell-out in CI unless the binary is present.
- Extend `checkout_happy_path_test.exs` to assert the delivered email
  carries one PDF attachment with the expected filename.

## Open questions for after #158

- Which snapshot fields exist on the placed Order, and do they cover
  every value the JSON payload needs (per-line VAT rate, promotion
  amount, fulfillment tax)?
- Does the snapshot store pre-formatted strings, or does the receipt
  module format at render time? Affects whether currency/date helpers
  live in `Receipt` or upstream.
