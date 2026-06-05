// Brand tokens — mirrors assets/css/app.css. OKLCH→sRGB conversions
// are perceptual, not bit-identical.

#let colors = (
  forest: rgb("#1f3a2c"),          // --color-forest
  forest-content: rgb("#f1ece0"),  // --color-forest-content
  cream: rgb("#f4ebd9"),           // --color-cream
  cream-content: rgb("#4d3c2c"),   // --color-cream-content
  rule: rgb("#e3dccb"),            // --color-base-300
  ink: rgb("#322c20"),             // --color-base-content
  ink-muted: rgb("#7a6f59"),
  honey: rgb("#e8c267"),           // --color-link-underline
)

// Fetch the .ttf files with ./fetch_fonts.sh, then pass
// `--font-path priv/receipts/fonts` to `typst compile`.
#let fonts = (
  sans: "Open Sans",
  serif: "Crimson Text",
)

#let type-scale = (
  eyebrow: 8.5pt,
  body: 10pt,
  small: 8.5pt,
  micro: 7.5pt,
  display: 26pt,    // section-title equivalent — masthead serif moment
  quote: 14pt,      // card-message pull-quote
)

// Sans, uppercase, tracked — mirrors `.eyebrow` in CSS.
#let eyebrow(body, fill: colors.ink-muted) = text(
  font: fonts.sans,
  size: type-scale.eyebrow,
  weight: "bold",
  tracking: 1.5pt,
  fill: fill,
  upper(body),
)

// Crimson Text, light, tight tracking — mirrors `.section-title` in CSS.
#let display(body, fill: colors.ink, size: type-scale.display) = text(
  font: fonts.serif,
  size: size,
  weight: "light",
  tracking: -0.2pt,
  fill: fill,
  body,
)

#let hairline = line(
  length: 100%,
  stroke: 0.5pt + colors.rule,
)

// 2pt honey underline. Set `length: auto` (default of `line`) so callers
// can size it to the text it accents.
#let honey-rule(length: 100%) = line(
  length: length,
  stroke: 2pt + colors.honey,
)
