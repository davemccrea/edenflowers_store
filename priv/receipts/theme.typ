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

#let hairline = line(
  length: 100%,
  stroke: 0.5pt + colors.rule,
)
