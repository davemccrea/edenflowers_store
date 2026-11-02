#import "@preview/tiaoma:0.3.0"
#import "theme.typ": colors, type-scale, eyebrow, hairline
#import "parts.typ": invoice-page, buyer-and-facts, line-items, vat-breakdown

// Render one invoice. `invoice` is a flat dict built by
// Edenflowers.Payments.InvoicePdf; see sample/invoice.*.json. Its own billed
// lines and VAT use the shared table layout. Money and dates arrive
// pre-formatted, labels translated, and the virtual barcode as its 54 digits.
#let invoice(invoice) = {
  let required = (
    "lang", "labels", "number", "invoice_date", "due_date", "late_interest_rate",
    "seller", "buyer", "line_items", "vat_breakdown", "amount", "reference_number", "virtual_barcode",
  )
  let optional = ("customer_reference", "supply_date", "supply_description")
  for key in required {
    assert(key in invoice, message: "invoice: missing required key `" + key + "`")
  }
  for key in optional {
    assert(key in invoice, message: "invoice: missing optional key `" + key + "` (set to none if absent)")
  }
  for key in ("name", "business_id", "address", "iban") {
    assert(key in invoice.seller, message: "invoice: seller missing `" + key + "`")
  }
  for key in ("company_name", "business_id", "name", "address") {
    assert(key in invoice.buyer, message: "invoice: buyer missing `" + key + "`")
  }

  let t(key) = invoice.labels.at(key)
  let num(body) = text(features: ("tnum",), body)

  // The seller's details are in the footer.
  show: invoice-page.with(invoice.seller, t, t("invoice"), invoice.number, invoice.lang)

  let facts = (
    (t("invoice-number"), str(invoice.number)),
    (t("invoice-date"), invoice.invoice_date),
    (t("due-date"), invoice.due_date),
    (t("reference-number"), invoice.reference_number),
    (t("late-interest"), invoice.late_interest_rate),
  )
  if invoice.supply_date != none {
    facts.push((if invoice.supply_description != none { invoice.supply_description } else { t("supply-date") }, invoice.supply_date))
  }
  if invoice.customer_reference != none {
    facts.push((t("your-reference"), invoice.customer_reference))
  }

  buyer-and-facts(invoice.buyer, facts, t)

  v(22pt)

  line-items(invoice.line_items, t, price-label: t("unit-price-incl-vat"))
  v(10pt)
  align(right)[
    #block(width: 60%)[
      #grid(
        columns: (1fr, auto), align: (left, right),
        text(weight: "bold", t("due-on-invoice")),
        num(text(weight: "bold", invoice.amount)),
      )
      #v(14pt)
      #vat-breakdown(invoice.vat_breakdown, t)
    ]
  ]

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
        columns: (1.6fr, 1fr, 1fr, 1fr),
        column-gutter: 14pt,
        row-gutter: 9pt,
        field(t("iban"), invoice.seller.iban),
        field(t("reference-number"), invoice.reference_number),
        field(t("due-date"), invoice.due_date),
        field(t("amount"), invoice.amount),
        grid.cell(colspan: 4, field(t("virtual-barcode"), invoice.virtual_barcode)),
      )
      #v(14pt)
      #align(center, tiaoma.code128(
        invoice.virtual_barcode,
        options: (show-hrt: false),
        width: 105mm,
        height: 12mm,
      ))
    ],
  )
}
