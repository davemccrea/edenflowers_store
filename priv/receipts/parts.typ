// Blocks the receipt and the invoice print the same way, so a customer sees
// one set of lines and one VAT breakdown whichever document they hold.
#import "theme.typ": colors, type-scale, eyebrow

// Column headers: quiet sans, mixed case, muted ink. Reserved for the
// section heading above; the hairline rule alone separates header from
// data. Eyebrow style stays unique to section-level labels.
#let head(label) = table.cell(
  text(size: type-scale.small, fill: colors.ink-muted)[#label]
)

// `t` looks a label up in the payload's translated labels.
#let line-items(items, t) = table(
  columns: (1fr, 110pt, 36pt, auto, 64pt),
  column-gutter: 8pt,
  align: (left, right, right, right, right),
  stroke: none,
  inset: (x: 0pt, y: 5pt),

  table.header(
    head(t("item")),
    head(t("unit-price-excl-vat")),
    head(t("quantity")),
    head(t("vat-rate")),
    head(t("total")),
    table.hline(stroke: 0.5pt + colors.rule),
  ),

  ..items.map(item => (
    [
      #item.product_name
      #if item.variant_size != none [
        (#item.variant_size)
      ]
    ],
    text(features: ("tnum",))[#item.unit_price_ex_tax],
    text(features: ("tnum",))[#item.quantity],
    text(features: ("tnum",))[#item.tax_rate],
    text(features: ("tnum",))[#item.total],
  )).flatten()
)

// The VAT is stated per rate, as AVL § 209 f asks of a business buyer's
// invoice and kuittipakkolaki 658/2013 § 4 of a receipt for an in-person
// payment (online sales fall outside that act). Prices are tax-inclusive, so the VAT is
// *contained* in the total: this block decomposes the figure above it
// and must never read as another addend, which is why it sits below
// the rule rather than in the column.
#let vat-breakdown(rows, t) = [
  #align(left, eyebrow(t("vat-breakdown")))
  #v(5pt)
  #table(
    columns: (auto, 1fr, 1fr, 1fr),
    align: (left, right, right, right),
    stroke: none,
    inset: (x: 0pt, y: 4pt),

    table.header(
      head(t("vat-rate")),
      head(t("net")),
      head(t("vat")),
      head(t("gross")),
      table.hline(stroke: 0.5pt + colors.rule),
    ),

    ..rows.map(row => (
      text(features: ("tnum",))[#row.rate],
      text(features: ("tnum",))[#row.base],
      text(features: ("tnum",))[#row.tax],
      text(features: ("tnum",))[#row.gross],
    )).flatten()
  )
]
