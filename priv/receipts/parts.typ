// These shared blocks give receipts, invoices and credit notes consistent line
// items and VAT breakdowns, so an invoice and its credit note look like a pair.
#import "theme.typ": colors, fonts, type-scale, eyebrow, display, hairline, honey-rule

#let shop = toml("shop.toml")

// This page layout puts the invoice or credit note's title at the top left and
// the logo at the top right, as on receipts. The seller's details are in the
// footer, as on most Finnish invoices. Use as `show: invoice-page.with(…)`.
#let invoice-page(seller, t, title, number, lang, body) = {
  set page(
    paper: "a4",
    margin: (top: 24mm, bottom: 22mm, x: 22mm),
    footer: context [
      #set text(font: fonts.sans, size: type-scale.micro, fill: colors.ink-muted)
      #hairline
      #v(6pt)
      #grid(
        columns: (1fr, auto),
        align: (left, right),
        [
          #seller.name · #seller.address · #t("business-id") #seller.business_id \
          #shop.email · #shop.phone
        ],
        [#counter(page).display() / #context counter(page).final().first()],
      )
    ],
  )

  set document(title: title + " " + str(number), author: seller.name, date: none)
  set text(font: fonts.sans, size: type-scale.body, fill: colors.ink, lang: lang)
  set par(leading: 0.65em, justify: false)

  grid(
    columns: (auto, 1fr),
    align: (left + top, right + top),
    [
      #display(title)
      #v(6pt)
      #box(honey-rule(length: 40pt))
    ],
    image("assets/logo.svg", height: 64pt),
  )

  v(14pt)

  body
}

// Show the buyer beside document facts supplied as (label, value) pairs.
// Address a company by name, with the person who ordered beneath it.
#let buyer-and-facts(buyer, facts, t) = {
  let lines(address) = if address != none { address.split("\n").join(linebreak()) }
  let buyer-lines = if buyer.company_name != none {
    (
      text(weight: "semibold", buyer.company_name),
      buyer.name,
      lines(buyer.address),
      [#t("business-id") #buyer.business_id],
    )
  } else {
    (text(weight: "semibold", buyer.name), lines(buyer.address))
  }

  grid(
    columns: (1fr, 1fr),
    column-gutter: 20pt,
    [
      #eyebrow(t("customer"))
      #v(5pt)
      #buyer-lines.filter(line => line != none).join(linebreak())
    ],
    grid(
      columns: (auto, auto),
      column-gutter: 12pt,
      row-gutter: 7pt,
      ..facts.map(((label, value)) => ([#label], text(features: ("tnum",), weight: "semibold", value))).flatten(),
    ),
  )
}

// Use small, mixed-case text in muted ink for column headers, reserving the
// uppercase eyebrow style for section headings. A thin rule separates the
// headers from the table's data.
#let head(label) = table.cell(
  text(size: type-scale.small, fill: colors.ink-muted)[#label]
)

// `t` looks a label up in the payload's translated labels.
// An invoice prints the unit price with VAT too (`incl-vat: true`), as its
// lines were priced that way; the VAT-exclusive one is what AVL § 209 e asks for.
#let line-items(items, t, incl-vat: false) = table(
  columns: if incl-vat { (1fr, auto, auto, auto, auto, 60pt) } else { (1fr, 110pt, 36pt, auto, 64pt) },
  column-gutter: 8pt,
  align: (left,) + (right,) * (if incl-vat { 5 } else { 4 }),
  stroke: none,
  inset: (x: 0pt, y: 5pt),

  table.header(
    head(t("item")),
    head(t("unit-price-excl-vat")),
    ..if incl-vat { (head(t("unit-price-incl-vat")),) },
    head(t("quantity")),
    head(t("vat-rate")),
    head(t("total")),
    table.hline(stroke: 0.5pt + colors.rule),
  ),

  ..items.map(item => (
    [
      #item.product_name
      #let choices = (item.variant_size, item.bow_colour).filter(c => c != none)
      #if choices.len() > 0 [
        (#choices.join(", "))
      ]
    ],
    text(features: ("tnum",))[#item.unit_price_ex_tax],
    ..if incl-vat { (text(features: ("tnum",))[#item.unit_price_incl_tax],) },
    text(features: ("tnum",))[#item.quantity],
    text(features: ("tnum",))[#item.tax_rate],
    text(features: ("tnum",))[#item.total],
  )).flatten()
)

// The VAT is stated per rate, as AVL § 209 f asks of a business buyer's
// invoice and kuittipakkolaki 658/2013 § 4 of a receipt for an in-person
// payment (online sales fall outside that act). Prices are tax-inclusive, so the VAT is
// already included in the total. Keep this breakdown separate from the totals
// grid so readers do not mistake its tax amounts for additional charges.
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
