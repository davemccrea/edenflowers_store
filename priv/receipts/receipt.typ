#import "theme.typ": colors, fonts, type-scale, eyebrow, display, hairline, honey-rule
#import "i18n.typ": translate

#let shop = toml("shop.toml")

// Render a single receipt. `order` is a flat dict whose keys mirror the
// Ash `Order` / `LineItem` attribute names; see sample/order.*.json.
// `shop` is loaded from shop.toml. All currency / date / VAT values
// arrive pre-formatted as strings; labels are translated via order.lang.
#let receipt(order) = {
  // Schema contract. Typst has no struct types, so we assert keys
  // exist up-front rather than discovering a missing field mid-render.
  // Required: read unconditionally on every receipt. Optional: key must
  // still be present in the dict; the value may be `none`.
  let required = (
    "lang", "order_reference", "ordered_at",
    "customer_name", "customer_email",
    "fulfillment_method", "fulfillment_date",
    "line_items", "vat_breakdown",
    "items_subtotal", "grand_total",
  )
  let optional = (
    "card_message",
    "recipient_name", "recipient_phone_number",
    "delivery_address", "delivery_instructions",
    "fulfillment_fee", "discount",
  )
  for key in required {
    assert(key in order, message: "receipt: missing required key `" + key + "`")
  }
  for key in optional {
    assert(key in order, message: "receipt: missing optional key `" + key + "` (set to none if absent)")
  }
  let line_item_required = (
    "product_name", "variant_size", "quantity",
    "unit_price_ex_tax", "tax_rate", "total",
  )
  for item in order.line_items {
    for key in line_item_required {
      assert(key in item, message: "receipt: line item missing `" + key + "`")
    }
  }
  for row in order.vat_breakdown {
    for key in ("rate", "base", "tax", "gross") {
      assert(key in row, message: "receipt: VAT breakdown row missing `" + key + "`")
    }
  }

  let t(key) = translate(key, order.lang)
  let fulfillment-label = if order.fulfillment_method == "delivery" {
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

  set document(
    title: t("receipt") + " " + order.order_reference,
    author: shop.name,
    date: none,
  )

  set text(font: fonts.sans, size: type-scale.body, fill: colors.ink, lang: order.lang)
  set par(leading: 0.65em, justify: false)

  // ── Masthead ────────────────────────────────────────────────────────
  // Serif "Receipt" leads the page — top-left is the reading-order anchor,
  // so the document type identifies itself before the brand mark. Logo
  // sits top-right as an editorial sign-off. Inline `Label: value` lines
  // use weight (not colour) to distinguish value from label — keeps the
  // page on one ink tone for content, one (muted) for chrome.
  grid(
    columns: (auto, 1fr),
    align: (left + top, right + top),
    [
      #display(t("receipt"))
      #v(8pt)
      #text(features: ("tnum",))[
        #t("reference"):
        #text(weight: "semibold")[#order.order_reference] \
        #t("order-date"): #text(weight: "semibold")[#order.ordered_at]
      ]
      #v(6pt)
      #box(honey-rule(length: 40pt))
    ],
    image("assets/logo.svg", height: 80pt),
  )

  v(18pt)

  // ── Customer + Fulfillment ──────────────────────────────────────────
  // Fulfillment block self-contains its date — no separate "Date" eyebrow.
  // The date is a property of the fulfillment (when to deliver / when to
  // collect), not a top-level field. Delivery and pickup share the same
  // shape: who/where, then a single inline date line at the bottom.
  let date-label = if order.fulfillment_method == "delivery" {
    t("delivery-date")
  } else {
    t("pickup-date")
  }

  // `recipient_name` is only stored for gift orders; a non-gift delivery goes
  // to the buyer, so name the buyer rather than leaving the line blank.
  let recipient = if order.recipient_name != none {
    order.recipient_name
  } else {
    order.customer_name
  }

  // Phone and instructions are optional, so collect the lines that are actually
  // present and join them — an absent one must not leave a blank line behind.
  let fulfillment-lines = if order.fulfillment_method == "delivery" {
    (
      text(weight: "semibold")[#recipient],
      order.recipient_phone_number,
      order.delivery_address,
      if order.delivery_instructions != none {
        text(font: fonts.serif, style: "italic")[#order.delivery_instructions]
      },
    )
  } else {
    // `recipient_phone_number` is mandatory for pickup precisely so Jennie can
    // text when the order is ready — the customer should see the number we hold.
    (
      text(weight: "semibold")[#shop.name],
      shop.address,
      order.recipient_phone_number,
    )
  }

  grid(
    columns: (1fr, 1fr),
    column-gutter: 20pt,
    [
      #eyebrow(t("customer"))
      #v(5pt)
      #text(weight: "semibold")[#order.customer_name] \
      #order.customer_email
    ],
    [
      #eyebrow(fulfillment-label)
      #v(5pt)
      #fulfillment-lines.filter(line => line != none).join(linebreak())
      #v(6pt)
      #date-label: #text(weight: "semibold")[#order.fulfillment_date]
    ],
  )

  // Tighter gap before the card-message annotation, so it sits closer to
  // its parent (Customer/Fulfillment) rather than reading as its own
  // section. If there's no message, the full section break carries
  // through to the Order section directly.
  v(if order.card_message != none { 12pt } else { 20pt })

  // ── Card message ────────────────────────────────────────────────────
  // Treated as an annotation, not a section: eyebrow + body-size serif
  // italic, no frame. Same voice as delivery instructions (also a
  // customer-authored aside).
  if order.card_message != none {
    eyebrow(t("card-message"))
    v(5pt)
    text(font: fonts.serif, style: "italic")[#order.card_message]
    v(20pt)
  }

  // ── Line items ──────────────────────────────────────────────────────
  eyebrow(t("order"))
  v(6pt)

  // Column headers: quiet sans, mixed case, muted ink. Reserved for the
  // section heading above; the hairline rule alone separates header from
  // data. Eyebrow style stays unique to section-level labels.
  let head(label) = table.cell(
    text(size: type-scale.small, fill: colors.ink-muted)[#label]
  )

  table(
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

    ..order.line_items.map(item => (
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

  v(10pt)

  // ── Totals ──────────────────────────────────────────────────────────
  // Single grid keeps row spacing under one `row-gutter` knob instead of
  // compounding paragraph spacing between separate grid calls. The
  // grand-total row is set off by a 0.5pt rule above (classic invoice
  // convention — "below the line") and a small size bump on the amount.
  let fee-label = if order.fulfillment_method == "delivery" {
    t("delivery-fee")
  } else {
    t("pickup-fee")
  }
  let totals-rows = (([#t("subtotal")], [#order.items_subtotal]),)
  if order.discount != none {
    totals-rows.push(([#t("discount")], [−#order.discount]))
  }
  if order.fulfillment_fee != none {
    totals-rows.push(([#fee-label], [#order.fulfillment_fee]))
  }

  // Three-column layout: label (auto), flexible gap (1fr), value (auto).
  // Auto-sizes labels to their widest content so locale variants like
  // Swedish "Hemleveransavgift" and "Betalat totalt" never wrap. The 1fr
  // gap keeps the value column flush-right within a 60% block.
  let row(label, value) = (
    [#label],
    [],
    text(features: ("tnum",))[#value],
  )

  align(right)[
    #block(width: 60%)[
      #grid(
        columns: (auto, 1fr, auto),
        align: (left, left, right),
        row-gutter: 7pt,
        ..totals-rows.map(r => row(..r)).flatten(),
        grid.cell(colspan: 3)[
          #v(2pt)
          #hairline
          #v(2pt)
        ],
        text(weight: "bold")[#t("total-paid")],
        [],
        text(features: ("tnum",), weight: "bold")[#order.grand_total],
      )

      #v(14pt)

      // ── VAT breakdown ─────────────────────────────────────────────────
      // Finnish receipts must state the VAT per rate — kuittipakkolaki
      // 658/2013 § 4, and AVL § 209 f for the simplified invoice every order
      // under €400 falls under. Prices are tax-inclusive, so the VAT is
      // *contained* in the total: this block decomposes the figure above it
      // and must never read as another addend, which is why it sits below
      // the rule rather than in the column.
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

        ..order.vat_breakdown.map(row => (
          text(features: ("tnum",))[#row.rate],
          text(features: ("tnum",))[#row.base],
          text(features: ("tnum",))[#row.tax],
          text(features: ("tnum",))[#row.gross],
        )).flatten()
      )
    ]
  ]

  // Minimum gap + elastic spacer. The minimum guarantees breathing
  // room above the band even when the page is dense; the `1fr` absorbs
  // all remaining vertical space so the band anchors to the bottom of
  // the content area on sparser layouts (pickup, few line items). On a
  // multi-page receipt the `1fr` has no slack to absorb and becomes a
  // no-op, so the band flows naturally after totals.
  v(20pt)
  v(1fr)

  // ── Closing band ────────────────────────────────────────────────────
  // Forest reverse-out, centred — mirrors the site's pull-quote section
  // (home_live.ex, .pull-quote on bg-forest). Thank-you in serif italic
  // carries the editorial moment; closing-line is supporting prose.
  block(
    width: 100%,
    fill: colors.forest,
    inset: (x: 24pt, y: 14pt),
    breakable: false,
    [
      #set align(center)
      #set text(fill: colors.forest-content)
      #text(font: fonts.serif, size: 15pt, style: "italic", weight: "light")[
        #t("thank-you")
      ]#h(4pt)#text(size: 12pt)[💛]
      #v(4pt)
      #set text(font: fonts.sans, size: type-scale.small,
                fill: colors.forest-content.transparentize(25%))
      #block(width: 80%)[#t("closing-line")]
    ],
  )
}
