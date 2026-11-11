#import "theme.typ": colors, fonts, type-scale, eyebrow, display, hairline, honey-rule
#import "parts.typ": line-items, vat-breakdown

#let shop = toml("shop.toml")

// Render a single receipt. `order` is a flat dict whose keys mirror the
// Ash `Order` / `LineItem` attribute names; see sample/order.*.json.
// `shop` (the pickup place and contact details) is loaded from shop.toml; the
// seller in the footer arrives in `order.seller`. All currency / date / VAT values
// arrive pre-formatted as strings; labels arrive translated by Gettext.
#let receipt(order) = {
  // Typst has no struct types, so assert that payload keys exist before rendering.
  // Required fields are read on every receipt. Optional fields must also have
  // keys in the dictionary, but their values may be `none`.
  let required = (
    "lang", "labels", "seller", "order_reference", "ordered_at",
    "customer_name", "customer_email",
    "fulfillment_method", "fulfillment_date",
    "line_items", "vat_breakdown",
    "items_subtotal", "grand_total",
    "payments",
  )
  let optional = (
    "card_message",
    "recipient_name", "contact_phone_number",
    "delivery_address", "delivery_instructions",
    "fulfillment_fee", "discount",
    "venue_name", "venue_address",
    "vat_note",
  )
  for key in required {
    assert(key in order, message: "receipt: missing required key `" + key + "`")
  }
  for key in optional {
    assert(key in order, message: "receipt: missing optional key `" + key + "` (set to none if absent)")
  }
  let line_item_required = (
    "product_name", "variant_size", "bow_colour", "quantity",
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
  for payment in order.payments {
    for key in ("method", "card_brand", "card_last4", "paid_on", "amount") {
      assert(key in payment, message: "receipt: payment missing `" + key + "`")
    }
  }

  let t(key) = order.labels.at(key)
  let fulfillment-label = if order.fulfillment_method == "delivery" {
    t("delivery")
  } else if order.fulfillment_method == "course" {
    t("course")
  } else if order.fulfillment_method == "gift-voucher" {
    t("gift-voucher")
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
          #order.seller.name · #order.seller.address · #t("business-id") #order.seller.business_id \
          #shop.email · #shop.phone
        ],
        [#counter(page).display() / #context counter(page).final().first()],
      )
    ],
  )

  set document(
    title: t("receipt") + " " + order.order_reference,
    author: order.seller.name,
    date: none,
  )

  set text(font: fonts.sans, size: type-scale.body, fill: colors.ink, lang: order.lang)
  set par(leading: 0.65em, justify: false)

  // ── Masthead ────────────────────────────────────────────────────────
  // Put the receipt title at the top left so readers identify the document
  // before seeing the logo at the top right. Inline `Label: value` lines use
  // font weight rather than colour to distinguish values from labels, keeping
  // one ink tone for content and a muted tone for supporting details.
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
  // Keep the delivery or pickup date inside the fulfillment block rather than
  // giving it a separate heading. Both blocks show who and where first,
  // followed by the date at the bottom.
  let date-label = if order.fulfillment_method == "delivery" {
    t("delivery-date")
  } else if order.fulfillment_method == "course" {
    t("course-date")
  } else if order.fulfillment_method == "gift-voucher" {
    t("valid-until")
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
      order.contact_phone_number,
      order.delivery_address,
      if order.delivery_instructions != none {
        text(font: fonts.serif, style: "italic")[#order.delivery_instructions]
      },
    )
  } else if order.fulfillment_method == "gift-voucher" {
    (
      [#t("voucher-for"): #text(weight: "semibold")[#order.recipient_name]],
      if order.at("collect_voucher_card", default: false) { t("voucher-collect") } else { t("voucher-emailed") },
    )
  } else if order.fulfillment_method == "course" {
    // Courses move between venues, so the receipt says where this one is.
    (
      text(weight: "semibold")[#order.venue_name],
      order.venue_address,
    )
  } else {
    // The phone is mandatory for pickup precisely so Jennie can text when the
    // order is ready — the customer should see the number we hold.
    (
      text(weight: "semibold")[#shop.name],
      shop.address,
      order.contact_phone_number,
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

  // Use a smaller gap before the card message to group it with the customer
  // and fulfillment details. Without a message, keep the full section gap
  // before the order lines.
  v(if order.card_message != none { 12pt } else { 20pt })

  // ── Card message ────────────────────────────────────────────────────
  // Style the card message as a customer-authored aside, like delivery
  // instructions: a small uppercase label and body-sized serif italics, without a frame.
  if order.card_message != none {
    // A voucher's message goes on the voucher, not a greeting card.
    eyebrow(if order.fulfillment_method == "gift-voucher" { t("voucher-message") } else { t("card-message") })
    v(5pt)
    text(font: fonts.serif, style: "italic")[#order.card_message]
    v(20pt)
  }

  // ── Line items ──────────────────────────────────────────────────────
  eyebrow(t("order"))
  v(6pt)

  line-items(order.line_items, t)

  v(10pt)

  // ── Totals ──────────────────────────────────────────────────────────
  // Keep totals in one grid so `row-gutter` controls their spacing without
  // adding paragraph gaps between separate grids. A thin rule and bold text
  // distinguish the grand total from the preceding amounts.
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

  // Size the label and value columns to their content, with a flexible gap
  // between them. This gives long translated labels room and keeps amounts
  // aligned to the right within the 60%-wide totals block.
  let row(label, value) = (
    [#label],
    [],
    text(features: ("tnum",))[#value],
  )

  // `method` is Stripe's payment method type or the in-person method. Stripe
  // can offer methods we have no label for, so those print as they come.
  let card-logos = ("visa", "mastercard", "amex")
  let method-labels = ("card", "zettle", "mobilepay", "klarna", "cash", "zervant", "voucher")
  let capitalized(name) = upper(name.first()) + name.slice(1).replace("_", " ")
  // The logo is sized to the cap height so a card row is no taller than the rest.
  let paid-with(payment) = if payment.card_brand in card-logos {
    box(baseline: 12%, image("assets/cards/" + payment.card_brand + ".svg", height: 8.5pt))
    h(5pt)
    text(features: ("tnum",))[•••• #payment.card_last4]
  } else if payment.card_brand != none [
    #capitalized(payment.card_brand) •••• #payment.card_last4
  ] else if payment.method in method-labels {
    t("method-" + payment.method)
  } else {
    capitalized(payment.method)
  }

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
        // List payment methods, dates and amounts beneath the total, as on a
        // till receipt. Older records without payment details arrive as an
        // empty payment list and do not add rows.
        ..if order.payments.len() > 0 { (grid.cell(colspan: 3)[#v(2pt)],) },
        ..order.payments.map(payment => (
          grid.cell(align: left + horizon, paid-with(payment)),
          grid.cell(align: right + horizon)[
            #text(features: ("tnum",), fill: colors.ink-muted)[#payment.paid_on]#h(12pt)
          ],
          grid.cell(align: right + horizon, text(features: ("tnum",))[#payment.amount]),
        )).flatten(),
      )

      #v(14pt)

      #if order.vat_breakdown.len() > 0 { vat-breakdown(order.vat_breakdown, t) }
      #if order.vat_note != none {
        // In this narrow column a lone last word is likely: weigh the breaks
        // across the whole note to avoid one.
        set par(linebreaks: "optimized")
        set text(costs: (runt: 1000%))
        align(left, text(size: type-scale.small, fill: colors.ink-muted)[#t("vat-note-" + order.vat_note)])
      }
    ]
  ]

  // Combine a minimum gap with a flexible spacer. The minimum keeps space
  // above the closing message even on a dense page; the `1fr` absorbs
  // all remaining vertical space so the message sits at the bottom of
  // the content area on sparser layouts (pickup, few line items). On a
  // multi-page receipt the `1fr` has no slack to absorb and becomes a
  // no-op, so the message follows the totals naturally.
  v(20pt)
  v(1fr)

  // ── Closing ─────────────────────────────────────────────────────────
  // Centre the closing message without a box. The honey rule echoes the header so
  // the page opens and closes on the same accent.
  block(
    width: 100%,
    breakable: false,
    [
      #set align(center)
      #box(honey-rule(length: 40pt))
      #v(10pt)
      #text(font: fonts.serif, size: 15pt, style: "italic", weight: "light", fill: colors.primary)[
        #t("thank-you")
      ]#h(4pt)#text(size: 12pt)[💛]
      #v(4pt)
      #text(font: fonts.sans, size: type-scale.small, fill: colors.ink-muted)[#t("closing-line")]
    ],
  )
}
