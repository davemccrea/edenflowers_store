# priv/receipts

Typst project for the order-receipt PDF emailed to customers.

## Preview locally

```sh
brew install typst   # one-time

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
