#import "invoice.typ": invoice

// Production path: Elixir invokes
//   typst compile invoice-main.typ out.pdf --input invoice=<json-encoded invoice>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   fi          (default, a company's booking fee: the first of two invoices)
//   fi.final    (the same wedding's independent remainder invoice)
//   sv          (a consumer's bespoke arrangement)
//   en.course   (a bespoke workshop invoice)
//   fi.part-paid (the booking fee resent after part of it was paid)
#let data = if "invoice" in sys.inputs {
  json(bytes(sys.inputs.invoice))
} else {
  let fixture = sys.inputs.at("fixture", default: "fi")
  json("sample/invoice." + fixture + ".json")
}

#invoice(data)
