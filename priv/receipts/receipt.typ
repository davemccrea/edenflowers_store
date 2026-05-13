#import "theme.typ": colors, fonts, type-scale, eyebrow, hairline
#import "i18n.typ": translate

#let shop = toml("shop.toml")

// Render a single receipt. `order` is a dict matching sample/order.*.json;
// `shop` is loaded from shop.toml. All currency / date / VAT values arrive
// pre-formatted as strings; labels are translated via order.lang.
#let receipt(order) = {
  let t(key) = translate(key, order.lang)
  let fulfillment-label = if order.fulfillment.method == "delivery" {
    t("delivery")
  } else {
    t("pickup")
  }
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
          #shop.name · #shop.address · #t("business-id") #shop.business_id \
          #shop.email · #shop.phone
        ],
        [#counter(page).display() / #context counter(page).final().first()],
      )
    ],
  )

  set text(font: fonts.sans, size: type-scale.body, fill: colors.ink)
  set par(leading: 0.65em, justify: false)

  // ── Masthead ────────────────────────────────────────────────────────
  grid(
    columns: (1fr, auto),
    align: (left + horizon, right + top),
    image("assets/logo.svg", height: 88pt),
    [
      #eyebrow(t("reference"))
      #v(2pt)
      #text(weight: "semibold")[#order.reference]
      #v(4pt)
      #order.ordered_at
    ],
  )

  v(18pt)
  hairline
  v(14pt)

  // ── Customer + Fulfillment ──────────────────────────────────────────
  grid(
    columns: (1fr, 1fr),
    column-gutter: 16pt,
    [
      #eyebrow(t("customer"))
      #v(6pt)
      #text(weight: "semibold")[#order.customer.name] \
      #order.customer.email
    ],
    [
      #eyebrow[#t("fulfillment") · #fulfillment-label]
      #v(6pt)
      #if order.fulfillment.method == "delivery" [
        #text(weight: "semibold")[#order.fulfillment.recipient_name] \
        #if order.fulfillment.recipient_phone != none [
          #order.fulfillment.recipient_phone \
        ]
        #order.fulfillment.address \
        #if order.fulfillment.instructions != none [
          #text(style: "italic", fill: colors.ink-muted)[
            #order.fulfillment.instructions
          ] \
        ]
      ] else [
        #text(weight: "semibold")[#t("pickup-at-shop")] \
        #shop.address
      ]
      #v(4pt)
      #eyebrow(t("date"))
      #v(2pt)
      #order.fulfillment.date
    ],
  )

  v(16pt)

  // ── Card message ────────────────────────────────────────────────────
  if order.card_message != none {
    block(
      width: 100%,
      fill: colors.cream,
      inset: (x: 14pt, y: 12pt),
      [
        #eyebrow(t("card-message"), fill: colors.cream-content)
        #v(6pt)
        #text(font: fonts.serif, size: 12pt, style: "italic",
              fill: colors.cream-content)[
          #order.card_message
        ]
      ],
    )
    v(14pt)
  }

  // ── Line items ──────────────────────────────────────────────────────
  eyebrow(t("order"))
  v(8pt)

  let head(label) = table.cell(eyebrow(label))

  table(
    columns: (1fr, 110pt, 36pt, 48pt, 64pt),
    column-gutter: 8pt,
    align: (left, right, right, right, right),
    stroke: none,
    inset: (x: 0pt, y: 6pt),

    head(t("item")),
    head(t("unit-price-excl-vat")),
    head(t("quantity")),
    head(t("vat")),
    head(t("total")),

    table.hline(stroke: 0.5pt + colors.rule),

    ..order.line_items.map(item => (
      [
        #text(weight: "semibold")[#item.name]
        #if item.variant_size != none [
          #text(fill: colors.ink-muted)[ (#item.variant_size)]
        ]
      ],
      text(features: ("tnum",))[#item.unit_price_ex_vat],
      text(features: ("tnum",))[#item.quantity],
      text(features: ("tnum",))[#item.vat_rate],
      text(features: ("tnum",), weight: "semibold")[#item.line_total],
    )).flatten()
  )

  v(6pt)

  // ── Totals ──────────────────────────────────────────────────────────
  // Single grid keeps row spacing under one `row-gutter` knob instead of
  // compounding paragraph spacing between separate grid calls.
  let fee-label = t("fulfillment-fee").replace("{method}", fulfillment-label)
  let totals-rows = (
    ([#t("subtotal")], [#order.totals.subtotal]),
    ([#fee-label], [#order.totals.fulfillment]),
  )
  if order.totals.discount != none {
    totals-rows.push(([#t("discount")], [−#order.totals.discount]))
  }
  totals-rows.push(([#t("vat")], [#order.totals.tax]))

  let row(label, value) = (
    [#label],
    text(features: ("tnum",))[#value],
  )

  let emphasis-row(label, value) = (
    text(weight: "bold")[#label],
    text(features: ("tnum",), weight: "bold")[#value],
  )

  align(right)[
    #block(width: 50%)[
      #grid(
        columns: (1fr, auto),
        align: (left, right),
        row-gutter: 7pt,
        ..totals-rows.map(r => row(..r)).flatten(),
        ..emphasis-row([#t("total-paid")], [#order.totals.grand_total]),
      )
    ]
  ]

  v(14pt)

  // ── Closing band ────────────────────────────────────────────────────
  block(
    width: 100%,
    fill: colors.forest,
    inset: (x: 16pt, y: 11pt),
    [
      #set text(fill: colors.forest-content, font: fonts.sans,
                size: type-scale.small)
      #set par(leading: 0.5em)
      #text(font: fonts.serif, size: 12pt, style: "italic")[
        #t("thank-you")
      ]
      #v(2pt)
      #t("closing-line")
    ],
  )
}
