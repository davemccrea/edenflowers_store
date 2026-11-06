# priv/receipts

Typst project for the PDFs the shop sends: the receipt emailed with orders and course bookings (`main.typ`, `receipt.typ`), the standalone invoice with its own billed lines and VAT (`invoice-main.typ`, `invoice.typ`), the credit note that cancels an invoice (`credit-note-main.typ`, `credit-note.typ`), and the pass-it-on cards for gift deliveries (`pass-it-on-main.typ`, `pass-it-on.typ`), one 85x55 mm card per two pages with 3 mm bleed. To print a batch, run `just print-cards` (see `mix help pass_it_on_cards`). `parts.typ` holds the line items and VAT breakdown they print, and the page, masthead and buyer block the invoice and credit note share. `Edenflowers.Orders.Receipt` and `Edenflowers.Payments.InvoicePdf` build the payloads; `Edenflowers.Typst` shells out to `typst`.

Typst is pinned to the version in `scripts/install-typst.sh` (`just install-typst`), which must match the Dockerfile and CI. Layout can shift between pre-1.0 releases.

## Preview locally

```sh
cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts                       # sv delivery
typst compile main.typ preview.pdf --font-path fonts --input fixture=en.pickup
typst compile invoice-main.typ preview.pdf --font-path fonts --package-path packages --input fixture=fi.final
typst compile credit-note-main.typ preview.pdf --font-path fonts --input fixture=sv
typst compile pass-it-on-main.typ preview.pdf --font-path fonts --package-path packages
typst compile voucher-main.typ preview.pdf --font-path fonts --input fixture=fi --input style=christmas
```

Fixtures are the files in `sample/` (`order.<fixture>.json`, `invoice.<fixture>.json`, `credit-note.<fixture>.json`), which also show the payload shape. Money, dates and VAT arrive pre-formatted as strings. The `lang` field sets Typst's text language. The `labels` dictionary arrives translated from the `receipts` Gettext domain, using the order, booking or invoice locale. Sample labels are snapshots for standalone Typst previews; update them alongside receipt and invoice translations.

## Fonts

Open Sans, Crimson Text and Noto Color Emoji are bundled under `fonts/` (SIL Open Font License 1.1, `fonts/OFL.txt`). Great Vibes, the Christmas voucher's greeting, is too (`fonts/OFL-GreatVibes.txt`).

## Voucher styles

`voucher.typ` prints a Gift voucher in cream, green or christmas (`style` in the payload). The Christmas snowflakes in `assets/snowflakes/` are one-colour SVGs from World of Printables, saved with `fill="#294735"` on the root so the template can recolour them. Their licence doesn't cover selling them on a voucher yet: see TASK-177 before deploying.

## Packages

The invoice prints its bank bar code with [tiaoma](https://typst.app/universe/package/tiaoma) (MIT, Zint inside), vendored under `packages/preview/tiaoma/0.3.0/` exactly as Typst Universe ships it. `--package-path packages` makes Typst find it there before its cache or the network, so rendering works offline in dev, CI and the release image. To upgrade, unpack the new version beside it and change the import in `invoice.typ`.
