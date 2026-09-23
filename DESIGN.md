---
name: Eden Flowers
description: A warm-paper editorial storefront where photographs lead, rules replace cards, and one honey stroke carries every affordance.
colors:
  primary: "oklch(0.3684 0.0478 156.76)"
  primary-content: "oklch(97% 0 0)"
  base-100: "oklch(99% 0.004 75)"
  base-200: "oklch(97% 0.008 75)"
  base-300: "oklch(93.5% 0.012 75)"
  base-content: "oklch(22% 0.015 75)"
  cream: "oklch(95% 0.025 75)"
  cream-content: "oklch(30% 0.05 60)"
  forest: "oklch(26% 0.05 152)"
  forest-content: "oklch(94% 0.02 80)"
  link-underline: "oklch(81% 0.15 93)"
typography:
  display:
    fontFamily: "Crimson Text, serif"
    fontSize: "3rem"
    fontWeight: 300
    lineHeight: 1.08
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "Crimson Text, serif"
    fontSize: "2.5rem"
    fontWeight: 400
    lineHeight: 1.15
    letterSpacing: "-0.025em"
  section:
    fontFamily: "Crimson Text, serif"
    fontSize: "1.875rem"
    fontWeight: 400
    lineHeight: 1.25
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Crimson Text, serif"
    fontSize: "1.5rem"
    fontWeight: 400
    lineHeight: 1.375
    letterSpacing: "normal"
  body:
    fontFamily: "Open Sans, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  label:
    fontFamily: "Open Sans, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.18em"
rounded:
  none: "0"
  selector: "0.5rem"
  full: "9999px"
spacing:
  gutter: "1rem"
  gutter-lg: "2rem"
  section-y: "5rem"
  section-y-lg: "9rem"
  header-height: "8rem"
  header-clearance: "calc(8rem + 3rem)"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-content}"
    rounded: "{rounded.none}"
    typography: "{typography.body}"
  button-primary-hover:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-content}"
    rounded: "{rounded.none}"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    rounded: "{rounded.none}"
  button-inverse:
    backgroundColor: "transparent"
    textColor: "#ffffff"
    rounded: "{rounded.none}"
  button-inverse-hover:
    backgroundColor: "#ffffff"
    textColor: "{colors.base-content}"
    rounded: "{rounded.none}"
  input:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.none}"
  radio-card:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.none}"
    padding: "0.75rem 1rem"
  product-mark:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.none}"
    padding: "0.4rem 0.75rem"
  eyebrow:
    textColor: "{colors.base-content}"
    typography: "{typography.label}"
---

# Design System: Eden Flowers

## Overview

**Creative North Star: "The Paper Florist"**

Everything sits on warm oat paper. A single serif — Crimson Text — carries the voice, and its italic is the closest thing the system has to handwriting. Sections are separated by a one-pixel rule, never by a card, never by a shadow, never by a change of background unless that change means something. Photographs run to the edge of the container or past it, and the interface never frames them: no radius, no border, no drop shadow, no caption box. The page is paper; the flowers are the ink.

The whole palette lives in one warm family. Every neutral sits at hue ~75 — oat, cream, near-black — so nothing on screen reads as cold grey. Forest green appears only where a section needs to reverse out entirely, and the deep green primary appears only on the things that act. One amber-honey stroke does all the interactive work: a 2px underline at a 0.3em offset, and nothing else. It never becomes a fill, a badge, or a body colour.

Density is generous and editorial. Sections breathe at 5–9rem of vertical padding, headings balance their own line breaks, and body copy avoids orphans. Interaction is quiet and physical: hover underlines fade in rather than pop, presses land instantly with a 1px downward translate and an opacity dip, and the release fades back. Motion is used for arrival and for photography — a 700ms rise on hero text, a 7s settle on hero photographs — and almost nowhere else.

**Key Characteristics:**
- Warm oat paper (hue ~75) under everything; no cold grey anywhere.
- Serif for voice, sans for interface — an absolute split.
- Square at the token level — `--radius-field` and `--radius-box` are `0`; only radios and status badges stay soft.
- Hairline rules instead of cards, panels, or elevation.
- One honey underline is the entire interactive vocabulary.
- Photographs are full-bleed and unframed; they carry the persuasion.
- Flat by default; a shadow must carry information to exist.

## Colors

A single warm family — paper at hue ~75, forest at hue ~150 — with one amber accent reserved entirely for interaction.

### Primary
- **Deep Muted Green** (`{colors.primary}`): the acting colour. Primary buttons, the wordmark in the header, focus outlines, the radio-card selected border and its 5% tint, the calendar override corner. Never used as a background for large areas.
- **Near-White Warm Grey** (`{colors.primary-content}`): text on the primary green. Sourced from Tailwind's `neutral-100`, the one token in the system that does not carry the warm hue, because it sits on green rather than on paper.

### Secondary
- **Amber Honey** (`{colors.link-underline}`): single-role by design. It is the underline colour on hover for serif headings and nav links, and the snapped underline on the active category-index entry and active size option. It appears as a 2px stroke and in no other form anywhere in the system.

### Tertiary
- **Warm Cream** (`{colors.cream}`): the editorial surface. Footer, callouts, banners, empty states, and the background behind product photography while it loads. One step warmer and more chromatic than `base-200`, so a cream block reads as a deliberate panel rather than as a slightly different white.
- **Dark Warm Brown** (`{colors.cream-content}`): text on cream.
- **Deep Forest Green** (`{colors.forest}`): the dark anchor for reverse-out sections. Used sparingly — three occurrences in the codebase.
- **Pale Warm Cream** (`{colors.forest-content}`): text and flower marks on forest.

### Neutral
- **Warm Off-White** (`{colors.base-100}`): the page. Header background, input backgrounds, the base of the product mark.
- **Light Warm Oat** (`{colors.base-200}`): the first tonal step up — admin table tracks, subtle recessed areas.
- **Warm Oat** (`{colors.base-300}`): the resting border of radio cards and floating menus, and hover fills in the admin sidebar. It is not the rule colour: at 93.5% on a 99% page it is too faint to structure anything. Rules use `base-content/12` (see The Hairline Rule).
- **Near-Black Warm Grey** (`{colors.base-content}`): all body and heading text. Its `/65`, `/70`, `/60`, `/40`, `/15`, `/12` and `/8` mixes are the system's entire secondary-text, rule and decoration scale — there is no separate muted-text token.

### Named Rules

**The One Family Rule.** Every surface, text and border colour sits at hue 60–80 (paper) or hue ~150 (forest). A colour outside those two families is a defect unless it is a semantic status colour inside `/admin`.

**The Admin Status Carve-out.** The admin is an operating tool, and its status colours are deliberately bright Tailwind palette (emerald, amber, orange, red) rather than the storefront's muted tokens. `.admin-theme` on the admin layout re-points `--color-success`, `--color-warning` and `--color-error` (and their `-content` text shades) at the palette, and the `admin-badge-*` pills use the Tailwind UI 50-fill / 700-text / 600-ring recipe. Keep that vividness inside `/admin`; it never leaks into the storefront.

**The Honey-Only Rule.** The amber accent exists as a 2px text-decoration and nothing else. Never a background, never a border, never a text colour, never a badge. Its scarcity is what makes an underline read as "this responds to you".

**The Opacity-Not-New-Token Rule.** Secondary text, dividers and decoration are produced by mixing `base-content` with transparency (`/70`, `/65`, `/40`, `/15`), not by adding grey tokens. Reach for an opacity step before proposing a new colour.

## Typography

**Display Font:** Crimson Text (with `serif` fallback) — self-hosted, static weights 400/600/700 plus matching italics.
**Body Font:** Open Sans (with `sans-serif` fallback) — self-hosted variable font covering weights 300–800, roman and italic.

**Character:** Crimson Text is a book serif with a real italic, and it does all the talking — headings, product names, prices, footer lines, pull quotes. Open Sans never speaks; it only labels. The pairing reads like a printed catalogue where the captions happen to be interactive.

### Hierarchy
- **Display** (`hero-display` — serif, 300, 3rem/1.08 → 3.75rem/1.04 → 4.5rem/1.02 → 5.5rem, tracking-tight to -0.01em, balanced): full-viewport hero headlines only. Set in italic on the home hero.
- **Headline** (`page-title` — serif, 400, 2.5rem/1.15 → 3rem/1.1, tracking-tight, balanced): the `h1` of an ordinary page.
- **Section** (`section-title` — serif, 400, 1.875rem/1.25 → 2.25rem, tracking-tight, balanced): section `h2`s.
- **Pull quote** (`pull-quote` — serif, 300, 1.875rem/1.25 → 2.25rem/1.2, tracking-tight, balanced): standalone editorial statements.
- **Title** (`card-title` / `tile-title` — serif, 400, 1.5rem/1.375, tracking-normal → wide at `sm`): product names and tile labels. `card-title` steps *down* to 1.25rem at `sm` because product cards get narrower in a grid; `tile-title` does not.
- **Footer line** (`footer-line` — serif, 1.125rem/1.375): address, hours, and the footer's quiet inventory of facts. Serif, because these are things the shop says, not things the interface says.
- **Body** (Open Sans, 400, 1rem/1.5): default. Prose pages step up to 1.125rem with `leading-relaxed` and cap at `max-w-2xl`. `main p` carries `text-wrap: pretty`.
- **Label** (`eyebrow` — sans, 700, 0.75rem, uppercase, 0.18em tracking): section category labels, footer column headings, the "From" prefix on prices.
- **Wordmark** (`logo-wordmark` — sans, 700, uppercase, 0.14em → 0.18em, 1.5rem → 1.875rem): the header's "Eden Flowers" lockup, set in primary green. The one place sans is allowed to be large.

### Named Rules

**The Serif-Sans Split Rule.** Serif is for what the shop says — headings, product names, prices, quotes, addresses, opening hours. Sans is for what the interface says about itself — eyebrows, buttons, nav, form labels, the wordmark. A serif button or a sans product name is a defect.

**The Open Price Rule.** A price is never smaller or fainter than the thing it prices: serif, upright, full `base-content`, `text-lg` or larger beside a title. No italic, no muted opacity, no `text-xs`. A price that whispers reads as one being hidden. Storefront prices go through `Format.price/2`, which drops the cents on whole euros.

**The Eyebrow Rule.** A section that needs a category label above its heading uses the eyebrow (0.75rem, 700, uppercase, 0.18em) at `base-content/70`. Never a smaller heading, never a coloured chip, never a pill.

**The Balanced Heading Rule.** Every display, headline, section and pull-quote utility carries `text-balance`. Body copy carries `text-wrap: pretty`. Neither is optional — Swedish and Finnish produce much longer strings than English, and unbalanced headings break first in those locales.

## Layout

A single centred container (`mx-auto px-4 sm:px-8`) governs horizontal rhythm, and full-bleed sections break out of it deliberately rather than by default.

- **Page wrapper:** the `.container` component adds `mt-28 mb-24`, stepping at `sm` to `--header-clearance` top and `mb-36` bottom. The offset exists because the header is fixed: `--header-height` is `8rem`, and `--header-clearance` adds twelve spacing steps on top. Use the token — two places were computing that `calc()` by hand.
- **Section rhythm:** `py-20` to `py-24` on small screens, `py-28` to `py-36` at `md`. Sections separate with `not-last:border-b` — a one-pixel rule, never a gap, never a background change on its own.
- **Header:** fixed, full viewport width, `z-50`, and *shy* — it translates fully out of view on scroll-down and returns on scroll-up over 200ms. Three-column flex: nav left, wordmark centre, account/locale/cart right. The desktop nav appears only at `xl`; below that it collapses into a drawer, because the nav carries eight items in three languages.
- **Anchors:** in-page anchors use `.scroll-anchor-below-header`, which offsets `scroll-margin-top` by the header height plus one spacing step so a heading never lands under the fixed header.
- **Footer:** a named-area grid that restructures three times — one column stacked, two columns at `sm`, four columns (`2fr 1fr 1fr 1fr`) at `lg`, with the newsletter always spanning the tallest area.
- **Breakpoints:** Tailwind defaults (`sm` 640, `md` 768, `lg` 1024, `xl` 1280). One bespoke breakpoint at 480px governs the carousel's slide basis. `xl` is the navigation breakpoint; `sm` is the typography and gutter breakpoint.
- **Product grid:** product figures are `aspect-[4/5]` on mobile and square at `sm` and up, with a matching per-breakpoint image crop rather than a CSS-cropped single source.

### Named Rules

**The Rule-Not-Card Rule.** Vertical separation between sections is a one-pixel border (`not-last:border-b`). Between full-width page sections it carries no colour class and so draws in full `base-content` ink; rules inside content use `base-content/12` (see The Hairline Rule). Do not introduce a card, a panel, a margin-only gap, or an alternating background to separate sections. A background change (`cream`, `forest`) is reserved for sections that are genuinely a different kind of thing.

**The Full-Bleed Rule.** Photographs run to the container edge or past it. On mobile the carousel deliberately breaks out to the viewport edges (`margin-inline: calc(50% - 50vw)`). Never frame a photograph with a border, a radius, a shadow, or a caption box.

## Elevation & Depth

Flat by default. Depth comes from three sources — the one-pixel rule, the tonal step between `base-100`, `base-200`, `cream` and `forest`, and the photograph itself. Buttons carry an explicit `shadow-none`. There is no elevation scale and none should be created.

A shadow is permitted only when it carries information: something genuinely floating above the page (drawer, modal, lightbox), or a signal the user could not otherwise get. The system currently has exactly one such shadow, and one exception that is drift.

### Shadow Vocabulary
- **Overflow cue** (`box-shadow: inset -0.75rem 0 0.75rem -0.75rem color-mix(in oklab, var(--color-base-content) 38%, transparent)`): on `.admin-table-scroll` below `lg`, telling the user a compact admin table continues horizontally. A scroll-driven animation shows it only while the table actually overflows and fades it out at the last column; browsers without `animation-timeline` get no cue. Functional — keep.
- **Lightbox credit** (`text-shadow: 0 1px 3px rgb(0 0 0 / 0.6)`): keeps the photographer credit legible over an arbitrary photograph in PhotoSwipe. Functional — keep.
- **Drift:** the portrait on `/maternity` carries `shadow-md`. It is decorative, it frames a photograph, and it should be removed.

### Named Rules

**The Functional-Shadow Rule.** A shadow must answer the question "what would the user not know without this?" Overflow, floating layers and legibility over photography qualify. Cards, buttons, inputs, tiles and images do not.

**The Gradient-For-Legibility Rule.** Text over a photograph is made legible by a gradient scrim (`from-black/50 via-black/15 to-transparent`, bottom-up), never by a solid box, a blur panel or a shadow on the text.

## Shapes

Square is the system. Buttons are explicitly `rounded-none` against daisyUI's default. Product figures, category tiles, the product mark, section rules and the header are all hard-cornered. The form language is a rectangle and a hairline.

- **Corners:** square is set at the token, not at the call site. The theme block pins daisyUI's `--radius-field` and `--radius-box` to `0`, so every input, select, textarea, dropdown, modal and drawer is square without any markup saying so. There are no radius utilities in the storefront or admin markup, and none should be added.
- **The radio carve-out:** `--radius-selector` deliberately keeps daisyUI's `0.5rem`. It shapes radios, and a square radio reads as a checkbox — the checkout fulfillment picker depends on that distinction. This is the one place softness is load-bearing.
- **No 0.25rem tier.** There used to be one — the radio card, the checkout date-picker frame, the admin warning banner, the admin calendar's cells, swatches and weekday chips, the admin nav's `rounded-r`, and the skip link all carried `0.25rem`. None of it was a deliberate tier: every one was hand-matching daisyUI's old `--radius-field` default. When that token went to `0` they were orphaned, and a soft radio card sitting above a square text input in the same checkout step is what it looked like. All removed.
- **Badges:** daisyUI rounds `.badge` with `--radius-selector`, so the admin status badges (confidence, payment, fulfillment, category) are soft pills. That is intended: a status reads as a tag, not as a field.
- **Pills:** `9999px` on the cart count badge, avatar initials, carousel dots, the calendar strike and the admin scrollbar thumb, where the shape *is* the meaning. These are the only curves left in the system.
- **Borders:** one pixel, in ink or `base-content/12` (see The Hairline Rule), used as separation rather than as containment. The product mark is the exception: a hairline frame at `base-content/55` over a 85%-opaque `base-100` backdrop with a 2px blur, so a label sits *on* a photograph instead of being burned into it.
- **Decoration:** line-drawn flower SVGs (`priv/svg/`, inlined at compile time, `fill: currentColor`) are the only ornament. They appear at low opacity (`/15`, `/70`) as watermarks in quiet corners — the footer's top-right, reverse-out sections. They are always `aria-hidden`.
- **Calendar primitives:** the admin fulfillment calendar has its own tiny shape vocabulary — a 45° strike through a closed cell (`::after`), a top-right triangle for a rule override (`::before`), and 45° repeating stripes for a mixed state. Two of them layer, which is why they use different pseudo-elements.

### Named Rules

**The Square Edge Rule.** Radius is `0`, set at the token so nothing has to remember. Exactly two exceptions exist: `--radius-selector` (radios stay circular, status badges stay pills) and `rounded-full` (things whose roundness is their meaning). `rounded-full` is the only radius utility in the entire codebase — nine of them. Any other radius in markup is a defect by construction, because the token already gives you square and a utility can only move away from it.

**The Orphan Rule.** A hand-written value that duplicates a token is a future defect. The old `0.25rem` sites were invisible until the token beneath them moved — then a radio card and the text input below it disagreed in the same form. If you find yourself typing a value that a token already sets, delete the value.

**The Hairline Rule.** Borders are 1px. If a boundary needs more weight than a hairline, it needs a different colour surface, not a thicker border. The weight comes from colour, in three steps:

- **Ink** (a bare `border-b`, which Tailwind v4 draws in `currentColor`, so full `base-content`): the rule between full-width page sections on the home and weddings pages. The one line that is meant to be seen from across the room. The admin does not use ink anywhere: tried on its sidebar, top bars, page-header and totals rules, it read heavier than the tool wants. Its strongest line is the `/12` rule.
- **Rule** (`border-base-content/12`): rules inside content (account, checkout steps, course details, FAQ), table and list edges, the edge of an admin panel, the admin sidebar and top bars, a totals rule.
- **Row** (`divide-base-content/8`): dividers between rows inside something that already has a rule around it, so the container still reads above its rows.

A tinted divider that carries meaning (the admin dashboard's overdue `divide-error/15` and today `divide-success/20`) keeps its tint. The admin used to draw its lines in `base-300/70` and `/50`, about half the contrast of the storefront's, and on a panel that sits on the same `base-100` as the page, that left the border as the only edge and made it nearly invisible. Do not reach for `base-300` to draw a line.

## Components

**Character: quiet, precise, physical.** Nothing shouts, edges are exact, and the press is the one place the system is unmistakably tactile — a control drops one pixel and dims to 0.9 the instant it is pressed, with `transition: none` so the press lands immediately, then fades back on release.

### Buttons
- **Shape:** hard corners (`0`), no shadow, sans, weight 500, normal case, normal tracking. Sizing comes from daisyUI's `btn-sm` / `btn-md` / `btn-lg` scale.
- **Primary:** deep green fill, near-white text (`btn-primary`).
- **Secondary:** green outline on transparent (`btn-primary btn-outline`).
- **Inverse:** white outline at 80% over photography; on hover and focus it fills white with `base-content` text. Its focus ring is overridden to white via `--focus-color`, because the default green ring disappears on a dark photograph.
- **Ghost / Destructive:** `btn-ghost`, and `btn-error btn-outline`.
- **Text:** not a button at all — it drops the `btn` class entirely and renders as an inline link with the static body underline, going to full-opacity underline on hover.
- **Press:** `opacity: 0.9; translate: 0 1px; transition: none` on `:active`, excluding disabled and link variants. Modelled on the Nord Design System.
- **Focus:** a 2px `currentColor` outline at 2px offset, recoloured to `--focus-color` (default primary) — applied globally, including on compound daisyUI fields that draw their outline on a wrapper rather than the input.

### Form buttons
The submit button swaps its label for a spinner, both sharing one grid cell so the width never shifts. The reveal is delayed 300ms, so a fast submit never flashes a spinner, and the swap back is instantaneous. The loading state is driven by LiveView's `.phx-submit-loading` class, never by a prop.

### Inputs / Fields
- **Style:** daisyUI `input input-lg`, full width, square, on `base-100`. Label above at `mb-1`, inside a flex-column `<label>` so the whole thing is one click target.
- **Trailing state:** a right-inset slot at `right-3` carries a spinner while validating, a green `check-circle` when confirmed, or arbitrary trailing content. Reserved space via `pr-10` so the value never slides.
- **Validation cadence:** `phx-debounce="blur"` until the field has been used, then live.
- **Error:** `input-error` border, `aria-invalid`, and an `aria-describedby` error node below.
- **Radio card:** a bordered row (`0.25rem`, `base-300`) that shifts to a primary border and a 5% primary tint via `has-[input:checked]`, with a tiny primary radio as the marker. Flex-column on mobile, row at `md`.
- **Button-addon:** a joined input + primary submit for single-field forms (newsletter, promo code).

### Cards / Containers
There are no cards. The product card is a link, a figure and two lines of text with nothing around them:
- **Figure:** `aspect-[4/5]` (square at `sm`), `bg-cream` behind the image so the loading state is warm rather than blank, `overflow-hidden`.
- **Image:** scales to 1.04 over 700ms `ease-out` on group hover.
- **Name:** `card-title`, with the honey underline fading in on group hover.
- **Price:** serif `text-lg` at full `base-content`, prefixed by the `eyebrow` utility reading "From".
- **Focus:** a full-bleed `::after` pseudo-element becomes a 2px primary border on `focus-visible`, so the ring frames the whole card rather than the text.

### Navigation
- **Desktop (`xl` and up):** a flat row of 0.875rem links with `tracking-wide` and the honey hover underline. No active state in the header.
- **Mobile (below `xl`):** a drawer opened by a `bars-3-bottom-left` icon, carrying the nav, sign-in and locale picker.
- **Header behaviour:** fixed and shy (see Layout).
- **Category index (Store):** the signature navigation. A vertical editorial list where each category is a serif word anchored by an eyebrow numeral, with its description revealed on the active entry and on hover/focus of inactive ones. The active entry carries a snapped honey underline. **No transitions — these state changes snap, by design.**

### Size picker (signature)
Three serif words in a row on the product page, the active one anchored by the same honey underline as the category index. The native radio is visually replaced but keeps its focus ring via `:has(input:focus-visible)`.

### Carousel (signature)
Embla, used for Favourites. On mobile it bleeds to the viewport edges and applies a focal-point effect — the hook writes `--embla-progress` per frame and CSS scales neighbours down by up to 8% and fades them by up to 45%, so the focused card pops. At `sm` and up it becomes a plain multi-card row and the focal effect is dropped entirely. Dots are 5px circles that stretch to 14px when selected. All of it is disabled under `prefers-reduced-motion`.

### Loading and connection states
While LiveView is disconnected, every top-level part of the layout except the flash group dims to 0.7 — but only after a 400ms delay, so sub-400ms socket flaps stay invisible — and stops taking clicks at once. Un-dimming starts immediately. Nothing else dims the page: slow clicks already have the topbar and the button spinner, and the first connect leaves the server-rendered page usable. The flash group stays crisp and interactive so the "Connection lost" toast remains readable and dismissible.

### Named Rules

**The Press Rule.** Every pressable control lands instantly: `opacity: 0.9`, `translate: 0 1px`, `transition: none`. The release fades back over 150ms. Do not add a scale, a ripple or a colour flash to a press.

**The Breathe-Don't-Pop Rule.** Hover underlines are permanently present and transparent; only their colour transitions in over 150ms. Active-state underlines snap with no transition. That difference is deliberate: hover is an invitation, active is a fact.

## Do's and Don'ts

### Do:
- **Do** set every new heading in Crimson Text and every new label, button and nav item in Open Sans. The split is absolute.
- **Do** separate sections with `not-last:border-b` and reach for `bg-cream` or `bg-forest` only when the section is genuinely a different kind of thing.
- **Do** let the radius tokens carry squareness. A component should need no radius utility at all; if you are typing one, the token is wrong or you are making an exception you have not justified.
- **Do** express secondary text and decoration as opacity steps on `base-content` (`/70`, `/65`, `/40`, `/15`) rather than introducing grey tokens.
- **Do** run photographs full-bleed and unframed, and make text over them legible with the bottom-up gradient scrim.
- **Do** put `text-balance` on every serif heading and let `main p` handle body rag — Swedish and Finnish strings are materially longer than English and break first.
- **Do** guard every new animation with `@media (prefers-reduced-motion: no-preference)`, the way every existing one is.
- **Do** give any visually-replaced control its focus ring back through `:has(input:focus-visible)`, as the size picker does.
- **Do** use `--focus-color` to recolour the focus ring when the default green would vanish against the surface, as the inverse button does over photography.

### Don't:
- **Don't** let the honey accent become anything other than a 2px underline at a 0.3em offset. No honey fills, borders, badges or text.
- **Don't** add a shadow that does not answer "what would the user not know without this?". There is no elevation scale and none should be created.
- **Don't** wrap content in a card, a panel or a bordered box to group it. Use a rule, a background family, or vertical space.
- **Don't** introduce a colour outside hue 60–80 or hue ~150, except for semantic status colours inside `/admin`.
- **Don't** drift toward the generic florist e-commerce template: no pastel pinks, script fonts, pill buttons, heart icons, soft drop shadows or stock bouquet photography.
- **Don't** bring SaaS dashboard chrome onto the storefront: no cards-in-cards, no elevated panels, no gradient CTAs, no coloured status pills.
- **Don't** reach for luxury-brand pastiche: no all-caps thin sans at large sizes, no black-and-gold, no borrowed-prestige letter-spacing. The wordmark is the only large sans in the system.
- **Don't** add any radius utility except `rounded-full`. `rounded-full` is the only one left in the codebase, storefront and admin alike — that is the invariant, not a coincidence.
- **Don't** hand-write a value a token already sets. That is how the `0.25rem` tier survived invisibly until the token under it moved.
- **Don't** square `--radius-selector`. Radios must stay circular.
- **Don't** transition an active state. Hover breathes; active snaps.
