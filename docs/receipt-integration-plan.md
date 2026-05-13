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
  that was emailed; matches #158's immutability story.
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

## Open questions for after #158

- Which snapshot fields exist on the placed Order, and do they cover
  every value the JSON payload needs (per-line VAT rate, promotion
  amount, fulfillment tax)?
- Does the snapshot store pre-formatted strings, or does the receipt
  module format at render time? Affects whether currency/date helpers
  live in `Receipt` or upstream.
