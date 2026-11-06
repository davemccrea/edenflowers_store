#import "theme.typ": colors, fonts, type-scale, hairline, honey-rule, eyebrow

#let shop = toml("shop.toml")

// A Gift voucher card, in the one language the buyer chose for whoever
// receives it. `voucher` is a flat dict, see sample/voucher.*.json. Labels
// arrive translated by Gettext; amounts and dates arrive pre-formatted.
//
// Cream inside a fine green border, so it prints well at home. The amount
// leads at the top, who it's for and the buyer's words fill the middle, and
// the code and last day run along the foot.
#let voucher(voucher) = {
  for key in ("lang", "labels", "seller", "amount", "code", "expires_on", "recipient_name", "message") {
    assert(key in voucher, message: "voucher: missing key `" + key + "` (set to none if absent)")
  }
  for key in ("gift-voucher", "for", "code", "valid-until", "how-to-use", "terms") {
    assert(key in voucher.labels, message: "voucher: missing label `" + key + "`")
  }

  let t(key) = voucher.labels.at(key)
  let label(key) = block(below: 4pt, text(size: type-scale.small, fill: colors.ink-muted)[#t(key)])

  set page(
    paper: "a5",
    flipped: true,
    margin: 14mm,
    fill: colors.cream,
    background: place(
      top + left,
      dx: 6mm,
      dy: 6mm,
      rect(width: 100% - 12mm, height: 100% - 12mm, stroke: 0.75pt + colors.primary.transparentize(40%)),
    ),
  )
  set document(title: t("gift-voucher"), author: voucher.seller.name, date: none)
  set text(font: fonts.sans, size: type-scale.body, fill: colors.cream-content, lang: voucher.lang)
  // Tight within a label and its value; groups are spaced apart explicitly.
  set par(leading: 0.6em, spacing: 5pt, justify: false)

  place(top + right, image("assets/logo.svg", height: 72pt))

  let value = [
    #eyebrow(t("gift-voucher"))
    #v(14pt)
    // Large serif figures carry a side bearing: pulled back so the amount
    // lines up with the eyebrow and rule.
    #text(font: fonts.serif, size: 72pt, fill: colors.primary, features: ("lnum",), top-edge: "cap-height", bottom-edge: "baseline")[
      #h(-0.04em)#voucher.amount
    ]
    #v(10pt)
    #box(honey-rule(length: 36pt))
  ]

  let gift = align(horizon, block(width: 78%)[
    #if voucher.recipient_name != none [
      #label("for")
      #text(font: fonts.serif, size: 22pt, fill: colors.ink)[#voucher.recipient_name]
      #v(8pt)
    ]
    #if voucher.message != none {
      text(font: fonts.serif, size: 13pt, style: "italic")[#voucher.message]
    }
  ])

  let foot = [
    #hairline
    #v(8pt)
    #grid(
      columns: (auto, auto, 1fr),
      column-gutter: 12mm,
      [
        #label("code")
        #text(size: 14pt, weight: "semibold", tracking: 1.6pt, features: ("tnum",), fill: colors.ink)[#voucher.code]
      ],
      [
        #label("valid-until")
        #text(size: 14pt, weight: "semibold", features: ("tnum",), fill: colors.ink)[#voucher.expires_on]
      ],
      align(right + bottom, text(size: type-scale.micro, fill: colors.ink-muted)[
        #voucher.seller.name · #shop.email · #shop.phone
      ]),
    )
    #v(6pt)
    #set par(leading: 0.5em)
    #text(size: type-scale.micro, fill: colors.ink-muted)[#t("how-to-use") #t("terms")]
  ]

  grid(columns: (1fr,), rows: (auto, 1fr, auto), value, gift, foot)
}
