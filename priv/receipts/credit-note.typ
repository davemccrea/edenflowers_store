#import "theme.typ": hairline
#import "parts.typ": invoice-page, buyer-and-facts, line-items, vat-breakdown

// Render one credit note: the hyvityslasku that cancels an invoice. `note` is
// a flat dict built by Edenflowers.Payments.InvoicePdf; see
// sample/credit-note.*.json. It prints on the invoice's page with the
// invoice's buyer, names the invoice it cancels and credits its amount, which
// arrives formatted as negative. There is nothing to pay, so it has no
// payment details or bar code. Its lines and VAT exactly reverse the original
// invoice's immutable numeric snapshot.
#let credit-note(note) = {
  let required = (
    "lang", "labels", "number", "credit_date", "invoice_number", "invoice_date",
    "seller", "buyer", "amount", "line_items", "vat_breakdown",
  )
  for key in required {
    assert(key in note, message: "credit note: missing required key `" + key + "`")
  }
  for key in ("customer_reference", "reason") {
    assert(key in note, message: "credit note: missing optional key `" + key + "` (set to none if absent)")
  }
  for key in ("name", "business_id", "address") {
    assert(key in note.seller, message: "credit note: seller missing `" + key + "`")
  }
  for key in ("company_name", "business_id", "name", "address") {
    assert(key in note.buyer, message: "credit note: buyer missing `" + key + "`")
  }

  let t(key) = note.labels.at(key)
  let num(body) = text(features: ("tnum",), body)

  show: invoice-page.with(note.seller, t, t("credit-note"), note.number, note.lang)

  let facts = (
    (t("credit-note-number"), str(note.number)),
    (t("credit-date"), note.credit_date),
    (t("invoice-number"), str(note.invoice_number)),
    (t("invoice-date"), note.invoice_date),
  )
  if note.customer_reference != none {
    facts.push((t("your-reference"), note.customer_reference))
  }

  buyer-and-facts(note.buyer, facts, t)

  v(28pt)

  if note.reason != none {
    [#t("reason"): #note.reason]
    v(14pt)
  }

  line-items(note.line_items, t, incl-vat: true)
  v(14pt)
  align(right, block(width: 60%, vat-breakdown(note.vat_breakdown, t)))
  v(14pt)
  hairline
  v(4pt)
  grid(
    columns: (1fr, auto),
    text(weight: "bold", size: 12pt, t("credited")),
    num(text(weight: "bold", size: 12pt, note.amount)),
  )
}
