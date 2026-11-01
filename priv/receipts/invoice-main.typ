#import "invoice.typ": invoice

// Production path: Elixir invokes
//   typst compile invoice-main.typ out.pdf --input invoice=<json-encoded invoice>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   fi          (default, a company's booking fee: the first of two invoices)
//   fi.final    (the same wedding's final invoice, after the booking fee)
//   sv          (a consumer's delivery order, partly paid by card first)
//   en.course   (a Course booking)
#let data = if "invoice" in sys.inputs {
  json(bytes(sys.inputs.invoice))
} else {
  let fixture = sys.inputs.at("fixture", default: "fi")
  json("sample/invoice." + fixture + ".json")
}

#invoice(data)
