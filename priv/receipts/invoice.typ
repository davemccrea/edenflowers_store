#import "@preview/tiaoma:0.3.0"
#import "theme.typ": colors, type-scale, eyebrow, hairline
#import "parts.typ": invoice-page, buyer-and-facts, line-items, vat-breakdown

// Render one invoice. `invoice` is a flat dict built by
// Edenflowers.Payments.InvoicePdf; see sample/invoice.*.json. The purchase's
// lines and totals have the receipt's shape. Money and dates arrive
// pre-formatted, labels translated, and the virtual barcode as its 54 digits.
#let invoice(invoice) = {
  let required = (
    "lang", "labels", "number", "invoice_date", "due_date",
    "order_reference", "fulfillment_method", "fulfillment_date",
    "seller", "buyer",
    "line_items", "vat_breakdown", "items_subtotal", "grand_total",
    "earlier_invoices", "amount", "reference_number", "virtual_barcode",
  )
  let optional = ("customer_reference", "fulfillment_fee", "discount", "paid_earlier")
  for key in required {
    assert(key in invoice, message: "invoice: missing required key `" + key + "`")
  }
  for key in optional {
    assert(key in invoice, message: "invoice: missing optional key `" + key + "` (set to none if absent)")
  }
  for key in ("name", "business_id", "address", "iban", "bic") {
    assert(key in invoice.seller, message: "invoice: seller missing `" + key + "`")
  }
  for key in ("company_name", "business_id", "name", "address", "email") {
    assert(key in invoice.buyer, message: "invoice: buyer missing `" + key + "`")
  }

  let t(key) = invoice.labels.at(key)
  let num(body) = text(features: ("tnum",), body)
  let seller = invoice.seller
  let buyer = invoice.buyer

  // The seller's details are in the footer, and again in the payment details.
  show: invoice-page.with(seller, t, t("invoice"), invoice.number, invoice.lang)

  let purchase-label = if invoice.fulfillment_method == "course" { t("course") } else { t("order") }
  let facts = (
    (t("invoice-number"), str(invoice.number)),
    (t("invoice-date"), invoice.invoice_date),
    (t("due-date"), invoice.due_date),
    (purchase-label, invoice.order_reference),
  )
  if invoice.customer_reference != none {
    facts.push((t("your-reference"), invoice.customer_reference))
  }

  buyer-and-facts(buyer, facts, t)

  v(18pt)

  // ── Line items ──────────────────────────────────────────────────────
  // The whole purchase, even on an invoice for only part of it: the totals
  // below say how much of it this invoice asks for.
  let date-label = if invoice.fulfillment_method == "delivery" {
    t("delivery-date")
  } else if invoice.fulfillment_method == "course" {
    t("course-date")
  } else {
    t("pickup-date")
  }

  grid(
    columns: (auto, 1fr),
    align: (left + bottom, right + bottom),
    eyebrow(purchase-label),
    text(size: type-scale.small)[#date-label: #text(weight: "semibold", invoice.fulfillment_date)],
  )
  v(6pt)

  line-items(invoice.line_items, t)

  v(10pt)

  // ── Totals ──────────────────────────────────────────────────────────
  let fee-label = if invoice.fulfillment_method == "delivery" { t("delivery-fee") } else { t("pickup-fee") }
  let row(label, value) = ([#label], [], num(value))
  let rule = grid.cell(colspan: 3)[#v(2pt) #hairline #v(2pt)]

  let totals-rows = (row(t("subtotal"), invoice.items_subtotal),)
  if invoice.discount != none {
    totals-rows.push(row(t("discount"), "−" + invoice.discount))
  }
  if invoice.fulfillment_fee != none {
    totals-rows.push(row(fee-label, invoice.fulfillment_fee))
  }

  // What this purchase was already billed or paid, so a final invoice reads
  // as the rest of it. Muted: these don't add up to the line below, which is
  // whatever Jennie chose to ask for now.
  let muted(body) = text(fill: colors.ink-muted, body)
  let earlier-rows = invoice.earlier_invoices.map(earlier => (
    muted[#t("invoice") #earlier.number, #earlier.invoice_date],
    [],
    num(muted(earlier.amount)),
  ))
  if invoice.paid_earlier != none {
    earlier-rows.push((muted(t("paid")), [], num(muted(invoice.paid_earlier))))
  }

  // The VAT breakdown sits beside the totals, decomposing the order total
  // rather than the amount due, which may be only part of it.
  grid(
    columns: (1fr, 1fr),
    column-gutter: 32pt,
    vat-breakdown(invoice.vat_breakdown, t),
    grid(
      columns: (auto, 1fr, auto),
      align: (left, left, right),
      row-gutter: 7pt,
      ..totals-rows.flatten(),
      rule,
      text(weight: "bold", t("total-paid")),
      [],
      num(text(weight: "bold", invoice.grand_total)),
      grid.cell(colspan: 3)[#v(6pt)],
      ..if earlier-rows.len() > 0 {
        (grid.cell(colspan: 3, eyebrow(t("earlier"))),)
      },
      ..earlier-rows.flatten(),
      ..if earlier-rows.len() > 0 { (rule,) },
      text(weight: "bold", size: 12pt, t("due-on-invoice")),
      [],
      num(text(weight: "bold", size: 12pt, invoice.amount)),
    ),
  )

  // Elastic, as on the receipt: the payment details anchor to the bottom of
  // a sparse page and follow on after the totals on a full one.
  v(20pt)
  v(1fr)

  // ── Payment details ─────────────────────────────────────────────────
  // What the payer types into their bank, or pastes as the virtual barcode,
  // or scans as the bar code. The bar code follows Finance Finland's Bank
  // Bar Code Guide: Code 128 set C, 105 mm wide, 12 mm high, 20 mm of quiet
  // zone either side, and no text directly above or below it.
  let field(label, value) = [
    #text(size: type-scale.small, fill: colors.ink-muted, label) \
    #num(text(weight: "semibold", value))
  ]

  block(
    width: 100%,
    breakable: false,
    stroke: 0.5pt + colors.rule,
    radius: 3pt,
    inset: (x: 14pt, y: 12pt),
    [
      #eyebrow(t("payment-details"))
      #v(8pt)
      #grid(
        columns: (1.3fr, 1.3fr, 1fr),
        column-gutter: 14pt,
        row-gutter: 9pt,
        field(t("payee"), seller.name),
        field(t("iban"), seller.iban),
        field(t("bic"), seller.bic),
        field(t("reference-number"), invoice.reference_number),
        field(t("due-date"), invoice.due_date),
        field(t("amount"), invoice.amount),
        grid.cell(colspan: 3, field(t("virtual-barcode"), invoice.virtual_barcode)),
      )
      #v(8pt)
      #text(size: type-scale.small)[#t("use-reference") #t("late-interest")]
      #v(10pt)
      #align(center, tiaoma.code128(
        invoice.virtual_barcode,
        options: (show-hrt: false),
        width: 105mm,
        height: 12mm,
      ))
    ],
  )
}
