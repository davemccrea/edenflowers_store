# priv/receipts

Typst project for the order-receipt PDF emailed to customers.

## Preview locally

Eden Flowers pins Typst to **0.14.2** — match the `TYPST_VERSION` arg in
the repo `Dockerfile`. Layout, kerning, and font fallback can shift
between pre-1.0 Typst releases, so receipts rendered against the wrong
version may not look identical to production.

```sh
brew install typst                                                # if Homebrew's `typst` is currently 0.14.2
# Otherwise, grab the pinned binary directly:
# https://github.com/typst/typst/releases/tag/v0.14.2

cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts                # default sv, delivery
typst compile main.typ preview.pdf --font-path fonts --input fixture=fi
typst compile main.typ preview.pdf --font-path fonts --input fixture=en.pickup
# fixtures: {en,fi,sv}[.pickup]
```

## Render from Elixir

```elixir
payload = order |> Edenflowers.Receipt.serialize() |> Jason.encode!()

{pdf, 0} =
  System.cmd("typst", [
    "compile",
    Path.join(:code.priv_dir(:edenflowers), "receipts/main.typ"),
    "-",
    "--format", "pdf",
    "--font-path", Path.join(:code.priv_dir(:edenflowers), "receipts/fonts"),
    "--input", "order=" <> payload
  ])
```

Attach via `Swoosh.Attachment.new({:data, pdf}, filename: "receipt-#{order.order_reference}.pdf", content_type: "application/pdf")`.

All currency / date / VAT values arrive **pre-formatted as strings** — see
`sample/order.en.json` for the canonical payload shape. The `lang` field
selects the column in `translations.toml`.

## Fonts

Open Sans, Crimson Text, and Noto Color Emoji are bundled under `fonts/` —
SIL Open Font License 1.1 (`fonts/OFL.txt`).
