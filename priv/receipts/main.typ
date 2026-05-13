#import "receipt.typ": receipt

// Production path: Elixir invokes
//   typst compile main.typ out.pdf --input order=<json-encoded order>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   en | fi | sv          (default sv, delivery)
//   en.pickup | fi.pickup | sv.pickup
#let order = if "order" in sys.inputs {
  // `json()` accepts bytes directly — `json.decode` is deprecated in
  // Typst 0.14 and removed in 0.15.
  json(bytes(sys.inputs.order))
} else {
  let fixture = sys.inputs.at("fixture", default: "sv")
  json("sample/order." + fixture + ".json")
}

#receipt(order)
