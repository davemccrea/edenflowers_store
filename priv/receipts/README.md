# priv/receipts

Typst project for the order-receipt PDF emailed to customers.

## Layout

- `theme.typ` — brand tokens (colors, fonts, type scale). Mirrors `assets/css/app.css`.
- `receipt.typ` — `receipt(order)` template.
- `i18n.typ` — `translate(key, lang)` helper over `translations.toml`.
- `main.typ` — entry point. Reads `sys.inputs.order` in production; falls back to a fixture for local preview.
- `translations.toml` — receipt labels in `en` / `fi` / `sv`.
- `shop.toml` — static shop identity (name, address, business ID, contact).
- `sample/order.{en,fi,sv}.json` — fixture payloads, one per locale.
- `fonts/` — Open Sans + Crimson Text `.ttf` files (OFL 1.1, see below).
- `assets/logo.svg` — brand logo.

## Preview locally

```sh
brew install typst   # one-time

cd priv/receipts
typst watch main.typ preview.pdf --font-path fonts                   # default sv
typst compile main.typ preview.pdf --font-path fonts --input fixture=fi
typst compile main.typ preview.pdf --font-path fonts --input fixture=en
```

`typst watch` recompiles on save for live preview.

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

## Order payload shape

See `sample/order.en.json` for the canonical example. Every value the template
displays — currency, dates, VAT rates, line totals — arrives **pre-formatted as
strings**, so locale rules stay in Elixir alongside the existing
`format_currency` / `format_date` helpers in `lib/edenflowers/email.ex`.

The `lang` field selects which row of `translations.toml` is used for labels.

## Fonts

Open Sans and Crimson Text are bundled under `fonts/`. Both are SIL Open Font
License 1.1 — see `fonts/OFL.txt`. Source projects:

- Open Sans: <https://github.com/googlefonts/opensans>
- Crimson Text: <https://github.com/Fonthausen/CrimsonPro>
