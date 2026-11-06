#import "theme.typ": colors, fonts, type-scale, honey-rule, eyebrow

#let shop = toml("shop.toml")

// Each style's inks: the gift side, and the stub that holds the money.
// Cream prints well at home; green fills the page, so it suits a voucher
// that's forwarded more than printed; Christmas is cream with snowflakes and
// a greeting.
#let cream-palette = (
  page: colors.cream,
  body: colors.cream-content,
  strong: colors.ink,
  muted: colors.ink-muted,
  stub: colors.primary,
  stub-ink: colors.cream,
  stub-muted: colors.cream.transparentize(30%),
)
#let palettes = (
  cream: cream-palette,
  christmas: cream-palette,
  green: (
    page: colors.primary,
    body: colors.cream,
    strong: colors.cream,
    muted: colors.cream.transparentize(30%),
    stub: colors.cream,
    stub-ink: colors.primary,
    stub-muted: colors.primary.transparentize(30%),
  ),
)

// The logo and snowflakes are one-colour SVGs, recoloured to suit the page.
#let recoloured(path, from, to, height) = image(bytes(read(path).replace(from, to.to-hex())), format: "svg", height: height)
#let logo(fill) = recoloured("assets/logo.svg", "#294634", fill, 72pt)
#let snowflake(n, height) = recoloured("assets/snowflakes/" + str(n) + ".svg", "#294735", colors.primary.lighten(72%), height)

#let stub-width = 74mm

// Snow on the gift side, kept to its right and top, clear of the text:
// (flake, x, y, size) from the page's top left. The SVGs pad each flake, so a
// size is about a third larger than the flake drawn.
#let snowfall = (
  (1, 96mm, 14mm, 10mm),
  (3, 112mm, 7mm, 5mm),
  (2, 125mm, 22mm, 7mm),
  (5, 86mm, 32mm, 5mm),
  (4, 108mm, 38mm, 8mm),
  (3, 129mm, 49mm, 5mm),
  (1, 120mm, 63mm, 9mm),
  (5, 131mm, 79mm, 6mm),
  (2, 117mm, 91mm, 6mm),
  (4, 128mm, 105mm, 8mm),
  (3, 112mm, 117mm, 5mm),
  (2, 124mm, 129mm, 6mm),
  (5, 130mm, 141mm, 4mm),
  (3, 34mm, 7mm, 4mm),
  (4, 62mm, 8mm, 5mm),
)

// A Gift voucher, in the one language the buyer chose for whoever receives
// it. `voucher` is a flat dict, see sample/voucher.*.json. Labels arrive
// translated by Gettext; amounts and dates arrive pre-formatted.
//
// A ticket: who it's to and the buyer's words fill the page, and a stub
// holds the amount, code and last day.
#let voucher(voucher) = {
  for key in ("lang", "labels", "seller", "style", "amount", "code", "expires_on", "recipient_name", "message") {
    assert(key in voucher, message: "voucher: missing key `" + key + "` (set to none if absent)")
  }
  for key in ("gift-voucher", "to", "code", "valid-until", "how-to-use", "terms") {
    assert(key in voucher.labels, message: "voucher: missing label `" + key + "`")
  }
  assert(voucher.style in palettes, message: "voucher: unknown style `" + voucher.style + "`")
  let christmas = voucher.style == "christmas"
  if christmas {
    assert("christmas-greeting" in voucher.labels, message: "voucher: missing label `christmas-greeting`")
  }
  let ink = palettes.at(voucher.style)

  let t(key) = voucher.labels.at(key)
  let stub-label(key) = block(below: 4pt, text(size: type-scale.small, fill: ink.stub-muted)[#t(key)])

  set page(
    paper: "a5",
    flipped: true,
    margin: 0mm,
    fill: ink.page,
    background: if christmas {
      for (n, x, y, size) in snowfall {
        place(top + left, dx: x - size / 2, dy: y - size / 2, snowflake(n, size))
      }
    },
  )
  set document(title: t("gift-voucher"), author: voucher.seller.name, date: none)
  set text(font: fonts.sans, size: type-scale.body, fill: ink.body, lang: voucher.lang)
  // Tight within a label and its value; groups are spaced apart explicitly.
  set par(leading: 0.6em, spacing: 5pt, justify: false)

  let gift = block(inset: (x: 15mm, y: 14mm), width: 100%, height: 100%, grid(
    rows: (auto, 1fr, auto),
    [
      #if christmas {
        text(font: "Great Vibes", size: 30pt, fill: colors.primary, bottom-edge: "descender")[#t("christmas-greeting")]
        v(6pt)
      }
      #eyebrow(t("gift-voucher"), fill: ink.muted)
    ],
    align(horizon, block(width: 88%)[
      #if voucher.recipient_name != none [
        #text(font: fonts.serif, size: 15pt, style: "italic", fill: ink.muted)[#t("to")]
        #v(2pt)
        // A long name drops a size rather than wrap onto a third line.
        #let name-size = if voucher.recipient_name.clusters().len() > 18 { 22pt } else { 30pt }
        #text(font: fonts.serif, size: name-size, fill: ink.strong)[#voucher.recipient_name]
        #v(10pt)
      ]
      #box(honey-rule(length: 36pt))
      #if voucher.message != none {
        v(10pt)
        text(font: fonts.serif, size: 14pt, style: "italic")[#voucher.message]
      }
    ]),
    block(width: 88%)[
      #set par(leading: 0.5em)
      #text(size: type-scale.micro, fill: ink.muted)[#t("how-to-use") #t("terms")]
      #v(6pt)
      #text(size: type-scale.micro, fill: ink.muted)[#voucher.seller.name · #shop.email · #shop.phone]
    ],
  ))

  let stub = block(fill: ink.stub, width: 100%, height: 100%, inset: (x: 10mm, y: 14mm), grid(
    rows: (auto, 1fr, auto),
    align(center, logo(ink.stub-ink)),
    align(center + horizon, text(
      font: fonts.serif,
      size: 52pt,
      fill: ink.stub-ink,
      features: ("lnum",),
      top-edge: "cap-height",
      bottom-edge: "baseline",
    )[#voucher.amount]),
    [
      #stub-label("code")
      #text(size: 11pt, weight: "semibold", tracking: 1.4pt, features: ("tnum",), fill: ink.stub-ink)[#voucher.code]
      #v(8pt)
      #stub-label("valid-until")
      #text(size: 11pt, weight: "semibold", features: ("tnum",), fill: ink.stub-ink)[#voucher.expires_on]
    ],
  ))

  grid(columns: (1fr, stub-width), rows: 100%, gift, stub)
}
