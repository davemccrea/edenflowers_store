#import "voucher.typ": voucher

// Production path: Elixir invokes
//   typst compile voucher-main.typ out.pdf --input voucher=<json-encoded voucher>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   sv | fi | en          (default sv)
#let data = if "voucher" in sys.inputs {
  json(bytes(sys.inputs.voucher))
} else {
  let fixture = sys.inputs.at("fixture", default: "sv")
  json("sample/voucher." + fixture + ".json")
}

#voucher(data)
