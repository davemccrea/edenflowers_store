#import "receipt.typ": receipt

// Production path: Elixir invokes
//   typst compile main.typ out.pdf --input order=<json-encoded order>
//
// Local preview falls back to a fixture. Override the language by
// setting --input fixture=en|fi|sv (default sv, matching the app's
// default locale).
#let order = if "order" in sys.inputs {
  json.decode(sys.inputs.order)
} else {
  let lang = sys.inputs.at("fixture", default: "sv")
  json("sample/order." + lang + ".json")
}

#receipt(order)
