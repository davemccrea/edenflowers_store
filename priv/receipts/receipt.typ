#import "theme.typ": colors, fonts, type-scale, eyebrow, section-title, hairline

// Render a single receipt. `order` is a dict with the shape produced by
// Edenflowers.Receipt.serialize/2 (see priv/receipts/sample/order.json for
// the canonical example).
//
// All currency values arrive pre-formatted as strings (e.g. "39,90 €") so
// the template never has to decide on locale rules.
#let receipt(order) = {
  // Page setup — A4, modest margins, page numbering in the footer for
  // multi-page orders (rare, but possible when there are many line items).
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
        [Eden Flowers · #order.shop.address_line],
        [#counter(page).display() / #context counter(page).final().first()],
      )
    ],
  )

  set text(font: fonts.sans, size: type-scale.body, fill: colors.ink)
  set par(leading: 0.65em, justify: false)

  // ── Masthead ─────────────────────────────────────────────────────────
  // Wordmark + receipt eyebrow on the left, reference + date on the right.
  // Mirrors the web layout pattern: serif + eyebrow stacked, with the
  // metadata anchored opposite.
  grid(
    columns: (1fr, auto),
    align: (left + horizon, right + top),
    [
      // Embedded vector — stays crisp at any zoom, doesn't bloat the
      // PDF. Height pinned; width is intrinsic so the logo's aspect
      // ratio is preserved. Sized so the circular wordmark and the
      // script signature underneath both read at A4 print size.
      #image("assets/logo.svg", height: 88pt)
    ],
    [
      #eyebrow[Reference]
      #v(2pt)
      #text(font: fonts.sans, size: type-scale.body, weight: "semibold")[
        #order.reference
      ]
      #v(4pt)
      #order.ordered_at
    ],
  )

  v(18pt)
  // Hairline divider — the logo carries the brand identity above; this
  // rule just separates masthead from content.
  hairline
  v(14pt)

  // ── Customer + Fulfillment ───────────────────────────────────────────
  // Two-column meta block: customer on the left, fulfillment on the right.
  // Eyebrow labels above each column keep the layout scannable.
  grid(
    columns: (1fr, 1fr),
    column-gutter: 16pt,
    [
      #eyebrow[Customer]
      #v(6pt)
      #text(weight: "semibold")[#order.customer.name] \
      #order.customer.email
    ],
    [
      #eyebrow[Fulfillment · #order.fulfillment.method_label]
      #v(6pt)
      // Method-specific block — delivery includes recipient + address;
      // pickup shows the shop address. Card message (if present) appears
      // below.
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
        #text(weight: "semibold")[Pickup at shop] \
        #order.shop.address_line
      ]
      #v(4pt)
      #eyebrow[Date]
      #v(2pt)
      #order.fulfillment.date
    ],
  )

  v(16pt)

  // ── Card message ────────────────────────────────────────────────────
  // Optional — only renders when the order is a gift and a message was
  // supplied. Cream tint card with serif italic body, echoing the
  // editorial pull-quote treatment.
  if order.card_message != none {
    block(
      width: 100%,
      fill: colors.cream,
      inset: (x: 14pt, y: 12pt),
      [
        #text(font: fonts.sans, size: type-scale.eyebrow, weight: "bold",
              tracking: 1.5pt, fill: colors.cream-content)[
          #upper[Card message]
        ]
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
  // Tabular numerals on the price column so cents align cleanly across
  // rows. Header row uses an eyebrow treatment.
  section-title[Order]
  v(6pt)

  // Header-cell shortcut — every column header uses the same eyebrow
  // treatment, so factoring it out keeps the table call readable.
  let head(label) = table.cell(
    text(
      font: fonts.sans,
      size: type-scale.eyebrow,
      weight: "bold",
      tracking: 1.5pt,
      fill: colors.ink-muted,
    )[#upper(label)],
  )

  table(
    // Five columns: item / unit ex VAT / qty / VAT% / line total.
    // Widths are sized for the eyebrow-tracked headers (the 1.5pt
    // letter-spacing on uppercase labels eats more width than the data
    // rows do), so the labels never wrap.
    columns: (1fr, 64pt, 36pt, 48pt, 64pt),
    align: (left, right, right, right, right),
    stroke: none,
    inset: (x: 5pt, y: 6pt),

    head[Item],
    head[Net unit],
    head[Qty],
    head[VAT %],
    head[Total],

    table.hline(stroke: 0.5pt + colors.rule),

    // Data rows — tabular nums (`tnum`) on every number column so cents
    // and percentages stack flush. Unit-ex-VAT and VAT% are muted; the
    // line total is the row's anchor and gets the semibold weight.
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
  // Right-aligned totals stack. Each row is a two-column grid row; the
  // whole block is one grid so vertical rhythm is controlled by
  // `row-gutter` instead of compounding paragraph spacing between
  // separate grid calls. Grand total picked out in forest green.
  let totals-rows = (
    ([Subtotal], [#order.totals.subtotal], false),
    (
      [#order.fulfillment.method_label fee],
      [#order.totals.fulfillment],
      false,
    ),
  )
  if order.totals.discount != none {
    totals-rows.push(([Discount], [−#order.totals.discount], false))
  }
  totals-rows.push(([Tax (incl.)], [#order.totals.tax], false))

  let row-cells(label, value, emphasis) = (
    text(
      fill: if emphasis { colors.forest } else { colors.ink },
      weight: if emphasis { "bold" } else { "regular" },
    )[#label],
    text(
      features: ("tnum",),
      fill: if emphasis { colors.forest } else { colors.ink },
      weight: if emphasis { "bold" } else { "regular" },
      size: if emphasis { 12pt } else { type-scale.body },
    )[#value],
  )

  align(right)[
    #block(width: 50%)[
      #grid(
        columns: (1fr, auto),
        align: (left, right),
        row-gutter: 7pt,
        ..totals-rows.map(r => row-cells(..r)).flatten(),
      )
      #v(7pt)
      #line(length: 100%, stroke: 0.5pt + colors.rule)
      #v(6pt)
      #grid(
        columns: (1fr, auto),
        align: (left, right),
        ..row-cells([Total paid], [#order.totals.grand_total], true),
      )
    ]
  ]

  v(14pt)

  // ── Footer note ─────────────────────────────────────────────────────
  // Forest band closes the receipt — matches the dark anchor used on the
  // web app's footer/banner sections. Kept low-height so the whole
  // receipt fits a single A4 page for typical line-item counts.
  block(
    width: 100%,
    fill: colors.forest,
    inset: (x: 16pt, y: 11pt),
    [
      #set text(fill: colors.forest-content, font: fonts.sans,
                  size: type-scale.small)
      #set par(leading: 0.5em)
      #text(font: fonts.serif, size: 12pt, style: "italic")[
        Thank you for your order.
      ]
      #v(2pt)
      Questions or changes? Reply to your confirmation email and Jennie
      will get back to you.
    ],
  )
}
