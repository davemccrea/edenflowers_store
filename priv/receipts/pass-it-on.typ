#import "@preview/tiaoma:0.3.0"
#import "theme.typ": colors, fonts, eyebrow

// Business cards for a print shop: 85x55 mm trimmed, two pages per card
// (logo side, then QR side), in code order. Each page carries 3 mm bleed on
// every side, so it is 91x61 mm, with no crop marks: the printer imposes the
// cards on its own sheets. Content keeps 5 mm inside the trim.

#let bleed = 3mm
#let safe = 5mm

// The wording Jennie approves before a print run. Swedish first.
#let copy = (
  sv: (
    heading: "Skicka vidare 💛",
    body: [Någon tänkte på dig idag. Skicka glädjen vidare: ge blommor till någon du tycker om, med 15 % rabatt.],
  ),
  fi: (
    heading: "Anna eteenpäin 💛",
    body: [Joku ajatteli sinua tänään. Anna ilo eteenpäin: lähetä kukkia jollekulle tärkeälle 15 %:n alennuksella.],
  ),
)

#let message(lang) = [
  #eyebrow(lang.heading, fill: colors.primary)
  #v(1.2mm, weak: true)
  // Black ink only: small text printed in four inks blurs if the plates are slightly out of register.
  #text(size: 7.5pt, fill: cmyk(0%, 0%, 0%, 100%), lang.body)
]

// The logo is drawn in one green; it's swapped for white on the green side.
#let white-logo = bytes(read("assets/logo.svg").replace("#294634", "#ffffff"))

#let logo-side = page(fill: colors.primary, align(center + horizon, image(white-logo, format: "svg", height: 32mm)))

#let qr-side(card) = align(horizon, grid(
  columns: (24mm, 1fr),
  column-gutter: 4mm,
  align: horizon,
  stack(
    spacing: 2mm,
    tiaoma.qrcode(card.url, width: 24mm),
    align(center, text(font: fonts.sans, size: 10pt, weight: "bold", tracking: 1.2pt, fill: colors.primary, card.code)),
  ),
  stack(spacing: 3mm, message(copy.sv), message(copy.fi)),
))

#let pass-it-on(data) = {
  set page(width: 85mm + 2 * bleed, height: 55mm + 2 * bleed, margin: bleed + safe)
  set text(font: fonts.sans, lang: "sv")
  for card in data.cards {
    logo-side
    page(qr-side(card))
  }
}
