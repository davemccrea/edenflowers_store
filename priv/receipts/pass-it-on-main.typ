#import "pass-it-on.typ": pass-it-on

// Production path: Elixir invokes
//   typst compile pass-it-on-main.typ out.pdf --input cards=<json-encoded batch>
//
// Local preview falls back to sample/pass-it-on.json.
#let data = if "cards" in sys.inputs {
  json(bytes(sys.inputs.cards))
} else {
  json("sample/pass-it-on.json")
}

#pass-it-on(data)
