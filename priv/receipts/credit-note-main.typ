#import "credit-note.typ": credit-note

// Production path: Elixir invokes
//   typst compile credit-note-main.typ out.pdf --input credit_note=<json-encoded credit note>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   fi          (default, cancelling a company's booking fee invoice, with a reason)
//   sv          (cancelling a consumer's invoice)
//   en.course   (cancelling a standalone bespoke workshop invoice)
#let data = if "credit_note" in sys.inputs {
  json(bytes(sys.inputs.credit_note))
} else {
  let fixture = sys.inputs.at("fixture", default: "fi")
  json("sample/credit-note." + fixture + ".json")
}

#credit-note(data)
