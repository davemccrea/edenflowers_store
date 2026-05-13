#import "receipt.typ": receipt

// Entry point. Two render paths:
//
//  1. Production — Elixir invokes:
//       typst compile main.typ out.pdf --input order=<json-encoded order>
//     The JSON blob is decoded and fed to receipt().
//
//  2. Local preview — run without --input and the fixture under
//     ./sample/order.json is used. Lets you iterate on the template with
//     `typst watch main.typ preview.pdf` without booting the app.
#let order = if "order" in sys.inputs {
  json.decode(sys.inputs.order)
} else {
  json("sample/order.json")
}

#receipt(order)
