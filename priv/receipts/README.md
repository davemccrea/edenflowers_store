# priv/receipts

Typst project for the PDFs the shop sends: the receipt emailed with orders and course bookings (`main.typ`, `receipt.typ`), and the invoice for a purchase on invoice terms (`invoice-main.typ`, `invoice.typ`). `parts.typ` holds the line items and VAT breakdown both print. `Edenflowers.Orders.Receipt` and `Edenflowers.Payments.InvoicePdf` build the payloads; `Edenflowers.Typst` shells out to `typst`.

Typst is pinned to the version in `scripts/install-typst.sh` (`just install-typst`), which must match the Dockerfile and CI. Layout can shift between pre-1.0 releases.

## Preview locally

```sh
cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts                       # sv delivery
typst compile main.typ preview.pdf --font-path fonts --input fixture=en.pickup
typst compile invoice-main.typ preview.pdf --font-path fonts --package-path packages --input fixture=fi.final
```

Fixtures are the files in `sample/` (`order.<fixture>.json`, `invoice.<fixture>.json`), which also show the payload shape. Money, dates and VAT arrive pre-formatted as strings. The `lang` field sets Typst's text language. The `labels` dictionary arrives translated from the `receipts` Gettext domain, using the order, booking or invoice locale. Sample labels are snapshots for standalone Typst previews; update them alongside receipt and invoice translations.

## Fonts

Open Sans, Crimson Text and Noto Color Emoji are bundled under `fonts/` (SIL Open Font License 1.1, `fonts/OFL.txt`).

## Packages

The invoice prints its bank bar code with [tiaoma](https://typst.app/universe/package/tiaoma) (MIT, Zint inside), vendored under `packages/preview/tiaoma/0.3.0/` exactly as Typst Universe ships it. `--package-path packages` makes Typst find it there before its cache or the network, so rendering works offline in dev, CI and the release image. To upgrade, unpack the new version beside it and change the import in `invoice.typ`.
