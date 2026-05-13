// Brand tokens — mirrors assets/css/app.css.
//
// CSS uses OKLCH; PDF needs sRGB. Hex values are the OKLCH-to-sRGB conversion
// of the source tokens, so they read the same warm/cool relationships in print
// as on screen but are not bit-identical.

#let colors = (
  // --color-forest: oklch(26% 0.05 152)
  forest: rgb("#1f3a2c"),
  // --color-forest-content: oklch(94% 0.02 80)
  forest-content: rgb("#f1ece0"),
  // --color-cream: oklch(95% 0.025 75)
  cream: rgb("#f4ebd9"),
  // --color-cream-content: oklch(30% 0.05 60)
  cream-content: rgb("#4d3c2c"),
  // --color-link-underline: oklch(81% 0.15 93)
  honey: rgb("#d9b14a"),
  // daisyUI light --color-primary: oklch(0.3684 0.0478 156.76)
  primary: rgb("#2b4a39"),
  // daisyUI light --color-base-100..300 / base-content
  paper: rgb("#fdfbf6"),
  paper-tint: rgb("#f7f2e7"),
  rule: rgb("#e3dccb"),
  ink: rgb("#322c20"),
  ink-muted: rgb("#7a6f59"),
)

#let fonts = (
  // Web app uses "Open Sans" / "Crimson Text" via Google Fonts. For PDF
  // rendering, place the .ttf files in ./fonts/ (see fetch_fonts.sh) and pass
  // `--font-path priv/receipts/fonts` to `typst compile`.
  sans: "Open Sans",
  serif: "Crimson Text",
)

// Type scale — tuned for an A4 receipt. Display size matches the web
// `.section-title` utility; body sits at a comfortable 10pt reading size.
#let type-scale = (
  display: 24pt,
  heading: 14pt,
  eyebrow: 8.5pt,
  body: 10pt,
  small: 8.5pt,
  micro: 7.5pt,
)

// Eyebrow utility — small-caps, wide tracking, mirrors `.eyebrow` in CSS.
#let eyebrow(body) = text(
  font: fonts.sans,
  size: type-scale.eyebrow,
  weight: "bold",
  tracking: 1.5pt,
  upper(body),
)

// Serif heading utility — mirrors `.section-title`.
#let section-title(body) = text(
  font: fonts.serif,
  size: type-scale.heading,
  weight: "regular",
  body,
)

// Hairline rule — same visual weight as `--color-rule` row dividers used
// across the web checkout.
#let hairline = line(
  length: 100%,
  stroke: 0.5pt + colors.rule,
)

// Honey underline — the brand's "active state" stroke. Used here under the
// document title to echo the link-underline pattern on the site.
#let honey-underline(body, thickness: 2pt, offset: 4pt) = {
  let content = box(body)
  stack(
    spacing: offset,
    content,
    line(length: measure(content).width, stroke: thickness + colors.honey),
  )
}
