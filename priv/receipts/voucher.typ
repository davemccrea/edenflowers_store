#import "theme.typ": colors, fonts, type-scale, honey-rule, eyebrow

#let shop = toml("shop.toml")

// One set of inks for every style: Christmas is cream with snowflakes and a
// greeting.
#let ink = (
  page: colors.cream,
  body: colors.cream-content,
  strong: colors.ink,
  muted: colors.ink-muted,
  stub: colors.primary,
  stub-ink: colors.cream,
  stub-muted: colors.cream.transparentize(30%),
)

// The logo and snowflakes are one-colour SVGs, recoloured to suit the page.
#let recoloured(path, from, to, height) = image(bytes(read(path).replace(from, to.to-hex())), format: "svg", height: height)
#let logo(fill) = recoloured("assets/logo.svg", "#294634", fill, 72pt)
#let snowflake(n, height, fill) = recoloured("assets/snowflakes/" + str(n) + ".svg", "#294735", fill, height)

#let stub-width = 74mm

// Small print that snow would make hard to read: (left, top, right, bottom)
// from the page's top left, with a little room around each.
#let small-print = (
  (12mm, 26mm, 46mm, 36mm), // "Gift voucher"
  (12mm, 112mm, 100mm, 140mm), // How to use it, the terms and the contact line
  (150mm, 8mm, 196mm, 44mm), // The logo's lettering
  (142mm, 110mm, 204mm, 140mm), // Code and last day
)
#let clear-of-small-print(x, y, size) = small-print.all(((left, top, right, bottom)) => (
  x + size < left or x > right or y + size < top or y > bottom
))

#let next(state) = calc.rem(state * 1103515245 + 12345, 2147483648)
#let pick(state, n) = calc.rem(calc.quo(state, 65536), n)

// Snow over the whole card: each side is cut into a grid and some cells get one
// flake, anywhere inside, so the snow is even and flakes never overlap. A small
// seeded generator picks the cells, flakes and sizes, so a voucher's snow is
// the same every time it's printed. (flake, x, y, size, fill) from the page's
// top left. The SVGs pad each flake, so a size is about a third larger than
// the flake drawn.
#let snowfall(seed) = {
  let rows = 8
  let row-height = 148mm / rows
  let sides = (
    (0mm, 210mm - stub-width, 8, colors.primary.lighten(72%)),
    (210mm - stub-width, stub-width, 4, colors.cream.transparentize(35%)),
  )
  let state = seed
  let flakes = ()
  for (left, width, columns, fill) in sides {
    let column-width = width / columns
    for column in range(columns) {
      for row in range(rows) {
        state = next(state)
        let snows = pick(state, 100) < 28
        state = next(state)
        let size = (4 + pick(state, 5)) * 1mm
        state = next(state)
        let x = left + column * column-width + pick(state, 11) / 10 * (column-width - size)
        state = next(state)
        let y = row * row-height + pick(state, 11) / 10 * (row-height - size)
        state = next(state)
        let flake = pick(state, 5) + 1
        if snows and clear-of-small-print(x, y, size) {
          flakes.push((flake, x, y, size, fill))
        }
      }
    }
  }
  flakes
}

// A Gift voucher, in the one language the buyer chose for whoever receives
// it. `voucher` is a flat dict, see sample/voucher.*.json. Labels arrive
// translated by Gettext; amounts and dates arrive pre-formatted.
//
// A ticket: who it's to and the buyer's words fill the page, and a stub
// holds the amount, code and last day.
#let voucher(voucher) = {
  for key in ("lang", "labels", "seller", "style", "snow_seed", "amount", "code", "expires_on", "recipient_name", "message") {
    assert(key in voucher, message: "voucher: missing key `" + key + "` (set to none if absent)")
  }
  for key in ("gift-voucher", "to", "code", "valid-until", "how-to-use", "terms") {
    assert(key in voucher.labels, message: "voucher: missing label `" + key + "`")
  }
  assert(voucher.style in ("cream", "christmas"), message: "voucher: unknown style `" + voucher.style + "`")
  let christmas = voucher.style == "christmas"
  // Vouchers sold without a seed, such as in the shop, all get the same snow.
  let seed = if voucher.snow_seed == none { 0 } else { voucher.snow_seed }
  if christmas {
    assert("christmas-greeting" in voucher.labels, message: "voucher: missing label `christmas-greeting`")
  }

  let t(key) = voucher.labels.at(key)
  let stub-label(key) = block(below: 4pt, text(size: type-scale.small, fill: ink.stub-muted)[#t(key)])

  set page(
    paper: "a5",
    flipped: true,
    margin: 0mm,
    fill: ink.page,
    // The stub's green is drawn here, under the snow, so flakes fall behind its text too.
    background: {
      place(top + right, rect(width: stub-width, height: 100%, fill: ink.stub))
      if christmas {
        for (n, x, y, size, fill) in snowfall(seed) {
          place(top + left, dx: x, dy: y, snowflake(n, size, fill))
        }
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

  let stub = block(width: 100%, height: 100%, inset: (x: 10mm, y: 14mm), grid(
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
