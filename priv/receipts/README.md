# priv/receipts

Typst project for the order-receipt PDF emailed to customers.

## Layout

- `theme.typ` — brand tokens (colors, fonts, type scale). Mirrors `assets/css/app.css`.
- `receipt.typ` — `receipt(order)` template.
- `main.typ` — entry point. Reads `sys.inputs.order` in production; falls back to `sample/order.json` for local preview.
- `sample/order.json` — fixture matching the payload shape `Edenflowers.Receipt` will emit.
- `fonts/` — Open Sans + Crimson Text `.ttf` files (gitignored — run `fetch_fonts.sh`).

## One-time setup

```sh
# Install typst (macOS)
brew install typst

# Fetch the two brand fonts
./fetch_fonts.sh
```

## Preview locally

```sh
cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts
```

`typst watch` recompiles on save so you can iterate on the template
without restarting the app.

## Render from Elixir

The Elixir caller passes the order as a JSON-encoded string via `--input`:

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

The PDF binary is then attached to the Swoosh email via
`Swoosh.Attachment.new({:data, pdf}, filename: "receipt-#{order.order_reference}.pdf", content_type: "application/pdf")`.

## Order payload shape

See `sample/order.json` for the canonical example. All currency / date values
arrive **pre-formatted as strings** so the template never has to know about
locale rules — that stays in Elixir alongside the existing
`format_currency` / `format_date` helpers in `lib/edenflowers/email.ex`.
