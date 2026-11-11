// These brand values mirror assets/css/app.css. The sRGB colours visually
// approximate the CSS OKLCH colours rather than matching them exactly.

#let colors = (
  primary: rgb("#294735"),         // --color-primary
  cream: rgb("#f9eddd"),           // --color-cream: oklch(95% 0.025 75) in sRGB
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
  display: 26pt,    // This is the serif masthead size, matching the section-title role in CSS.
  quote: 14pt,      // This size is intended for card-message quotations.
)

// Match `.eyebrow` in CSS with uppercase sans-serif text and wide letter spacing.
#let eyebrow(body, fill: colors.ink-muted) = text(
  font: fonts.sans,
  size: type-scale.eyebrow,
  weight: "bold",
  tracking: 1.5pt,
  fill: fill,
  upper(body),
)

// Match `.section-title` in CSS with light Crimson Text and tight letter spacing.
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

// This honey-coloured underline accepts an explicit length so callers can
// size it to the text it accents.
#let honey-rule(length: 100%) = line(
  length: length,
  stroke: 2pt + colors.honey,
)
