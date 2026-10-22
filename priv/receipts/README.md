# priv/receipts

Typst project for the receipt PDF emailed with orders and course bookings. `Edenflowers.Orders.Receipt` builds the payload and shells out to `typst`.

Typst is pinned to the version in `scripts/install-typst.sh` (`just install-typst`), which must match the Dockerfile and CI. Layout can shift between pre-1.0 releases.

## Preview locally

```sh
cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts                       # sv delivery
typst compile main.typ preview.pdf --font-path fonts --input fixture=en.pickup
```

Fixtures are the files in `sample/` (`order.<fixture>.json`), which also show the payload shape. Money, dates and VAT arrive pre-formatted as strings. The `lang` field picks the column in `translations.toml`.

## Fonts

Open Sans, Crimson Text and Noto Color Emoji are bundled under `fonts/` (SIL Open Font License 1.1, `fonts/OFL.txt`).
