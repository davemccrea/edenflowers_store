#import "theme.typ": colors, fonts, type-scale, eyebrow

#let shop = toml("shop.toml")

// All styles share these base colours. Christmas styles add snowflakes,
// a greeting and the accent colour defined below.
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

// Each Christmas voucher has one accent for its stub, greeting and snow:
// cranberry or brand green. Everything else is cream and the usual dark ink.
#let christmas-accents = (
  christmas: rgb("#8c2a2e"),
  christmas_green: colors.primary,
)

// Keep snow away from these small-print areas to preserve readability.
// Each rectangle is (left, top, right, bottom), measured from the page's top left
// and padded to leave space around the text.
#let small-print = (
  (12mm, 26mm, 46mm, 36mm), // Keep the gift-voucher heading clear.
  (12mm, 112mm, 100mm, 140mm), // Keep instructions, terms and contact details clear.
  (150mm, 8mm, 196mm, 44mm), // Keep the logo's lettering clear.
  (142mm, 110mm, 204mm, 140mm), // Keep the code and expiry date clear.
)
#let clear-of-small-print(x, y, size) = small-print.all(((left, top, right, bottom)) => (
  x + size < left or x > right or y + size < top or y > bottom
))

#let next(state) = calc.rem(state * 1103515245 + 12345, 2147483648)
#let pick(state, n) = calc.rem(calc.quo(state, 65536), n)

// Divide both sides of the card into grids and place at most one snowflake
// inside each cell, distributing the snow without overlapping flakes. A small
// seeded generator picks the cells, flakes and sizes, so a voucher's snow is
// the same every time it's printed. Each result is (flake, x, y, size, fill),
// with coordinates measured from the page's top left. The SVGs pad each flake,
// so its size is about a third larger than the flake drawn.
#let snowfall(seed, accent) = {
  let rows = 8
  let row-height = 148mm / rows
  let sides = (
    (0mm, 210mm - stub-width, 8, accent.lighten(72%)),
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

// Render a gift voucher in the language the buyer chose for its recipient.
// `voucher` is a flat dictionary; see sample/voucher.*.json. Labels arrive
// translated by Gettext; amounts and dates arrive pre-formatted.
//
// Use a ticket layout: the recipient and buyer's message fill the main area,
// while the stub holds the amount, code and expiry date.
#let voucher(voucher) = {
  for key in ("lang", "labels", "seller", "style", "snow_seed", "amount", "code", "expires_on", "recipient_name", "message") {
    assert(key in voucher, message: "voucher: missing key `" + key + "` (set to none if absent)")
  }
  for key in ("gift-voucher", "to", "code", "valid-until", "how-to-use", "terms") {
    assert(key in voucher.labels, message: "voucher: missing label `" + key + "`")
  }
  assert(voucher.style == "cream" or voucher.style in christmas-accents, message: "voucher: unknown style `" + voucher.style + "`")
  let christmas = voucher.style in christmas-accents
  let accent = christmas-accents.at(voucher.style, default: none)
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
    // Draw the stub's background before the snow so flakes appear behind its text too.
    background: {
      place(top + right, rect(width: stub-width, height: 100%, fill: if christmas { accent } else { ink.stub }))
      if christmas {
        for (n, x, y, size, fill) in snowfall(seed, accent) {
          place(top + left, dx: x, dy: y, snowflake(n, size, fill))
        }
      }
    },
  )
  set document(title: t("gift-voucher"), author: voucher.seller.name, date: none)
  set text(font: fonts.sans, size: type-scale.body, fill: ink.body, lang: voucher.lang)
  // Keep labels close to their values and add space between groups explicitly.
  set par(leading: 0.6em, spacing: 5pt, justify: false)

  let gift = block(inset: (x: 15mm, y: 14mm), width: 100%, height: 100%, grid(
    rows: (auto, 1fr, auto),
    [
      #if christmas {
        text(font: "Great Vibes", size: 30pt, fill: accent, bottom-edge: "descender")[#t("christmas-greeting")]
        v(6pt)
      }
      #eyebrow(t("gift-voucher"), fill: ink.muted)
    ],
    align(horizon, block(width: 88%)[
      #if voucher.recipient_name != none [
        #text(font: fonts.serif, size: 15pt, style: "italic", fill: ink.muted)[#t("to")]
        #v(2pt)
        // Use smaller text for long names to reduce the chance of a third line.
        #let name-size = if voucher.recipient_name.clusters().len() > 18 { 22pt } else { 30pt }
        #text(font: fonts.serif, size: name-size, fill: ink.strong)[#voucher.recipient_name]
        #v(10pt)
      ]
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
