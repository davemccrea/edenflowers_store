#import "theme.typ": colors, type-scale, hairline
#import "parts.typ": invoice-page, buyer-and-facts

// Render one credit note: the hyvityslasku that cancels an invoice. `note` is
// a flat dict built by Edenflowers.Payments.InvoicePdf; see
// sample/credit-note.*.json. It prints on the invoice's page with the
// invoice's buyer, names the invoice it cancels and credits its amount, which
// arrives formatted as negative. There is nothing to pay, so it has no
// payment details or bar code, and it leaves out the purchase's lines, which
// may have changed since the invoice was made.
#let credit-note(note) = {
  let required = (
    "lang", "labels", "number", "credit_date", "credits",
    "order_reference", "fulfillment_method", "seller", "buyer", "amount",
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
  for key in ("company_name", "business_id", "name", "address", "email") {
    assert(key in note.buyer, message: "credit note: buyer missing `" + key + "`")
  }

  let t(key) = note.labels.at(key)
  let num(body) = text(features: ("tnum",), body)

  show: invoice-page.with(note.seller, t, t("credit-note"), note.number, note.lang)

  let purchase-label = if note.fulfillment_method == "course" { t("course") } else { t("order") }
  let facts = (
    (t("credit-note-number"), str(note.number)),
    (t("credit-date"), note.credit_date),
    (purchase-label, note.order_reference),
  )
  if note.customer_reference != none {
    facts.push((t("your-reference"), note.customer_reference))
  }

  buyer-and-facts(note.buyer, facts, t)

  v(28pt)

  text(weight: "semibold", note.credits)
  if note.reason != none {
    v(4pt)
    [#t("reason"): #note.reason]
  }

  v(14pt)
  hairline
  v(4pt)
  grid(
    columns: (1fr, auto),
    text(weight: "bold", size: 12pt, t("credited")),
    num(text(weight: "bold", size: 12pt, note.amount)),
  )
  v(10pt)
  text(size: type-scale.small, fill: colors.ink-muted, t("nothing-to-pay"))
}
