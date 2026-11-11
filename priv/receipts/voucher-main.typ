#import "voucher.typ": voucher

// Production path: Elixir invokes
//   typst compile voucher-main.typ out.pdf --input voucher=<json-encoded voucher>
//
// Local preview falls back to a fixture. Override via `--input fixture=…`:
//   sv | fi | en          (default sv)
// Override the style via `--input style=cream|christmas|christmas_green` and the snow via `--input seed=…`.
#let data = if "voucher" in sys.inputs {
  json(bytes(sys.inputs.voucher))
} else {
  let fixture = sys.inputs.at("fixture", default: "sv")
  let sample = json("sample/voucher." + fixture + ".json")
  sample + (
    style: sys.inputs.at("style", default: sample.style),
    snow_seed: int(sys.inputs.at("seed", default: "0")),
  )
}

#voucher(data)
