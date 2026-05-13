#import "@preview/tiaoma:0.3.0": qrcode
#import "theme.typ": colors, fonts, type-scale, eyebrow, display, hairline, honey-rule
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
  // Serif "Receipt" leads the page — top-left is the reading-order anchor,
  // so the document type identifies itself before the brand mark. Logo
  // sits top-right as an editorial sign-off. Inline `Label: value` lines
  // use weight (not colour) to distinguish value from label — keeps the
  // page on one ink tone for content, one (muted) for chrome.
  // QR encodes the customer-facing tracking URL. Reference is unguessable
  // (random hex, 48 bits of entropy) so the URL alone is hard to enumerate;
  // the tracking page should additionally email-gate on access.
  let tracking-url = shop.tracking_base_url + "/" + order.reference

  grid(
    columns: (auto, 1fr),
    align: (left + top, right + top),
    [
      #display(t("receipt"))
      #v(8pt)
      #grid(
        columns: (auto, auto),
        column-gutter: 8pt,
        align: (left + horizon, left + horizon),
        // option-1: 2 → Zint QR error-correction level M (~15% tolerance).
        // Matches laskutys; balances scan reliability against module density.
        box(width: 48pt, height: 48pt, link(tracking-url, qrcode(
          tracking-url,
          options: (option-1: 2),
        ))),
        text(size: type-scale.small, fill: colors.ink-muted)[#t("track-order")],
      )
      #v(4pt)
      #text(features: ("tnum",))[
        #t("reference"):
        #text(weight: "semibold")[#order.reference] \
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
  let date-label = if order.fulfillment.method == "delivery" {
    t("delivery-date")
  } else {
    t("pickup-date")
  }

  grid(
    columns: (1fr, 1fr),
    column-gutter: 20pt,
    [
      #eyebrow(t("customer"))
      #v(5pt)
      #text(weight: "semibold")[#order.customer.name] \
      #order.customer.email
    ],
    [
      #eyebrow(fulfillment-label)
      #v(5pt)
      #if order.fulfillment.method == "delivery" [
        #text(weight: "semibold")[#order.fulfillment.recipient_name] \
        #if order.fulfillment.recipient_phone != none [
          #order.fulfillment.recipient_phone \
        ]
        #order.fulfillment.address \
        #if order.fulfillment.instructions != none [
          #text(font: fonts.serif, style: "italic")[
            #order.fulfillment.instructions
          ] \
        ]
      ] else [
        #text(weight: "semibold")[#shop.name] \
        #shop.address
      ]
      #v(6pt)
      #date-label: #text(weight: "semibold")[#order.fulfillment.date]
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
    columns: (1fr, 110pt, 36pt, 48pt, 64pt),
    column-gutter: 8pt,
    align: (left, right, right, right, right),
    stroke: none,
    inset: (x: 0pt, y: 5pt),

    head(t("item")),
    head(t("unit-price-excl-vat")),
    head(t("quantity")),
    head(t("vat")),
    head(t("total")),

    table.hline(stroke: 0.5pt + colors.rule),

    ..order.line_items.map(item => (
      [
        #item.name
        #if item.variant_size != none [
          (#item.variant_size)
        ]
      ],
      text(features: ("tnum",))[#item.unit_price_ex_vat],
      text(features: ("tnum",))[#item.quantity],
      text(features: ("tnum",))[#item.vat_rate],
      text(features: ("tnum",))[#item.line_total],
    )).flatten()
  )

  v(10pt)

  // ── Totals ──────────────────────────────────────────────────────────
  // Single grid keeps row spacing under one `row-gutter` knob instead of
  // compounding paragraph spacing between separate grid calls. The
  // grand-total row is set off by a 0.5pt rule above (classic invoice
  // convention — "below the line") and a small size bump on the amount.
  let fee-label = t("fulfillment-fee").replace("{method}", fulfillment-label)
  let totals-rows = (
    ([#t("subtotal")], [#order.totals.subtotal]),
    ([#fee-label], [#order.totals.fulfillment]),
  )
  if order.totals.discount != none {
    totals-rows.push(([#t("discount")], [−#order.totals.discount]))
  }
  totals-rows.push(([#t("vat")], [#order.totals.tax]))

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
        text(features: ("tnum",), weight: "bold")[#order.totals.grand_total],
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
      ]
      #v(4pt)
      #set text(font: fonts.sans, size: type-scale.small,
                fill: colors.forest-content.transparentize(25%))
      #block(width: 80%)[#t("closing-line")]
    ],
  )
}
