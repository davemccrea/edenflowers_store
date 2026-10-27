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
  eyebrow:
    textColor: "{colors.base-content}"
    typography: "{typography.label}"
---

# Design System: Eden Flowers

## Overview

**Creative North Star: "The Paper Florist"**

Everything sits on warm oat paper. A single serif, Crimson Text, carries the shop's voice, and its italic is the closest thing the system has to handwriting. Sections are separated by a one-pixel rule, never by a card, a shadow, or a change of background that doesn't mean something. Photographs run to the edge of the container or past it, and the interface never frames them. The page is paper; the flowers are the ink.

The palette is one warm family. Every neutral sits at hue ~75 (oat, cream, near-black), so nothing reads as cold grey. Forest green appears only where a section reverses out entirely, and the deep green primary only on things that act. One amber-honey stroke does all the interactive work: a 2px underline, and nothing else.

Density is generous and editorial. Interaction is quiet and physical: hover underlines fade in, presses land instantly with a 1px drop and an opacity dip. Motion is for arrival and photography, and almost nowhere else.

The admin is an operating tool and follows the same tokens with three deliberate differences: sans headings, bright status colours, and bordered panels.

**Key Characteristics:**
- Warm oat paper (hue ~75) under everything; no cold grey.
- Serif for the shop's voice, sans for the interface. The admin and the reference pages (FAQ, terms, privacy) are sans throughout.
- Square at the token level; the only curves are radios, status badges and pills.
- Hairline rules instead of cards, panels or elevation on the storefront.
- One honey underline is the whole interactive vocabulary.
- Photographs are full-bleed and unframed; they carry the persuasion.
- Flat by default; a shadow must carry information to exist.

## Colors

Paper at hue ~75 and forest at hue ~150, with one amber accent reserved for interaction.

### Primary
- **Deep Muted Green** (`{colors.primary}`): the acting colour. Primary buttons, the wordmark, focus outlines, and the selected state of choices (border plus a 5% tint). Never a large background.
- **Near-White** (`{colors.primary-content}`): text on primary. The one token without the warm hue, because it sits on green rather than paper.

### Secondary
- **Amber Honey** (`{colors.link-underline}`): the hover underline on headings and links, and the snapped underline on an active index entry or size. Nothing else.

### Tertiary
- **Warm Cream** (`{colors.cream}`): the editorial surface for the footer, callouts, banners, empty states, and behind photographs while they load. Warmer than `base-200`, so a cream block reads as deliberate.
- **Dark Warm Brown** (`{colors.cream-content}`): text on cream.
- **Deep Forest Green** (`{colors.forest}`): reverse-out sections, used sparingly.
- **Pale Warm Cream** (`{colors.forest-content}`): text and flower marks on forest.

### Neutral
- **Warm Off-White** (`{colors.base-100}`): the page, the header, inputs.
- **Light Warm Oat** (`{colors.base-200}`): the first tonal step: recessed areas, the admin sidebar.
- **Warm Oat** (`{colors.base-300}`): soft edges that are not structure: the resting border of a choice that turns primary when selected, floating menus, admin secondary buttons, admin hover fills. Too faint to structure a page.
- **Near-Black Warm Grey** (`{colors.base-content}`): all text, and through opacity, every secondary text, rule and decoration.

### Named Rules

**The One Family Rule.** Every surface, text and border colour sits at hue 60–80 or ~150. Anything else is a defect, unless it is an admin status colour.

**The Admin Status Carve-out.** Admin status colours are bright Tailwind palette (emerald, amber, orange, red), re-pointed under `.admin-theme`, so a problem reads as one before any row is opened. That vividness never leaks into the storefront.

**The Honey-Only Rule.** The amber accent is a 2px text-decoration at a 0.3em offset and nothing else: never a fill, border, text colour or badge. Its scarcity is what makes an underline read as "this responds to you".

**The Opacity-Not-New-Token Rule.** Secondary text, rules and decoration are `base-content` at an opacity: roughly `/85` to `/60` for secondary text, `/50` to `/15` for faint text and decoration, `/20` and `/12` for rules. Reach for an existing step before proposing a new colour.

## Typography

**Display Font:** Crimson Text (with `serif` fallback), self-hosted, 400/600/700 plus italics.
**Body Font:** Open Sans (with `sans-serif` fallback), self-hosted variable font, 300–800.

**Character:** Crimson Text is a book serif with a real italic, and it does the talking on the storefront. Open Sans labels; it speaks only where a page is a tool or a document. The pairing reads like a printed catalogue whose captions happen to be interactive.

### Hierarchy
- **Display** (`hero-display`: serif, 300, 3rem → 5.5rem): full-viewport hero headlines only; italic on the home hero.
- **Headline** (`page-title`: serif, 400, 2.5rem → 3rem): an ordinary page's `h1`.
- **Section** (`section-title`: serif, 400, 1.875rem → 2.25rem): section `h2`s.
- **Pull quote** (`pull-quote`: serif, 300, 1.875rem → 2.25rem): standalone editorial statements.
- **Title** (`card-title` / `tile-title`: serif, 400, 1.5rem): product names and tile labels.
- **Footer line** (`footer-line`: serif, 1.125rem): addresses, hours, the footer's facts.
- **Body** (sans, 400, 1rem/1.5): default. Prose pages step up to 1.125rem, relaxed leading, `max-w-2xl`.
- **Label** (`eyebrow`: sans, 700, 0.75rem, uppercase, 0.18em): category labels, footer headings, the "From" before a price.
- **Wordmark** (`logo-wordmark`: sans, 700, uppercase, wide tracking): the header lockup in primary green. The only large uppercase sans.
- **Reference and admin headings** (sans, 600, tracking-tight): headings on FAQ, terms and privacy, and every admin heading.

### Named Rules

**The Serif-Sans Split Rule.** On the storefront, serif is what the shop says (headings, product names, prices, quotes, addresses, hours) and sans is what the interface says about itself (eyebrows, buttons, nav, form labels). A serif button or a sans product name is a defect. The admin and the reference pages are sans throughout, headings included: one is a tool, the others are documents people consult rather than pages that persuade.

**The Open Price Rule.** A price is never smaller or fainter than what it prices: serif, upright, full `base-content`, `text-lg` or larger beside a title. Storefront prices go through `Format.storefront_price/2`, which drops the cents on whole euros.

**The Eyebrow Rule.** A category label above a heading is the eyebrow at `/70`. Never a smaller heading, a coloured chip or a pill.

**The Balanced Heading Rule.** Every heading utility carries `text-balance`, and body copy `text-wrap: pretty`. Swedish and Finnish strings run much longer than English and break first.

## Layout

One centred container (`mx-auto px-4 sm:px-8`) sets the horizontal rhythm; full-bleed sections break out of it on purpose.

- **Header:** fixed and *shy*: it slides out on scroll-down and back on scroll-up. It publishes its visible height as `--shy-header-offset`, so sticky elements sit just below it. Page tops clear it with `--header-clearance`, and anchors with `.scroll-anchor-below-header`; never hand-compute the offset.
- **Sections:** 5rem to 9rem of vertical padding, separated by `not-last:border-b`.
- **Navigation breakpoint:** the desktop nav appears at `xl`; below that it is a drawer, because eight items in three languages don't fit.
- **Reference pages:** a sticky section index beside the content from `md`.
- **Product figures:** `4/5` on phones, square from `sm`, each with its own crop rather than one CSS-cropped source.

### Named Rules

**The Rule-Not-Card Rule.** Sections separate with a one-pixel rule. Between full-width page sections it is ink; inside content it is `base-content/12`. Never a card, a margin-only gap or an alternating background. A background change (`cream`, `forest`) is reserved for a section that is genuinely a different kind of thing.

**The Full-Bleed Rule.** Photographs run to the container edge or past it, and are never framed with a border, radius, shadow or caption box. The one exception is the contact page's portrait of Jennie, a circle beside her details on phones, like an avatar.

## Elevation & Depth

Flat by default. Depth comes from the one-pixel rule, the tonal steps between `base-100`, `base-200`, `cream` and `forest`, and the photograph itself. There is no elevation scale and none should be created.

The shadows that exist each answer a question: the flash toast floats over any page; the admin sidebar's edge stays visible beside sticky headers; an admin page casts a shadow during its push transition; a compact admin table shows that it scrolls; the lightbox credit stays legible over any photograph.

### Named Rules

**The Functional-Shadow Rule.** A shadow must answer "what would the user not know without this?" Floating layers, overflow and legibility over photography qualify. Cards, buttons, inputs, tiles and images do not.

**The Gradient-For-Legibility Rule.** Text set over a photograph on a page is made legible by a bottom-up gradient scrim (`from-black/50 via-black/15 to-transparent`), never a solid box, a blur panel or a text shadow. The lightbox credit is the exception: there is no room for a scrim.

## Shapes

Square is the system: a rectangle and a hairline. Line-drawn flower SVGs, at low opacity and `aria-hidden`, are the only ornament.

### Named Rules

**The Square Edge Rule.** Radius is `0`, set at the token (`--radius-field` and `--radius-box`), so markup never has to say so. Two exceptions: `--radius-selector` keeps daisyUI's `0.5rem`, because a square radio reads as a checkbox and status badges read as tags; and `rounded-full`, for things whose roundness is their meaning (count badges, avatars, dots, the contact portrait). `rounded-full` is the only radius utility allowed; `DesignRulesTest` enforces it.

**The Orphan Rule.** A hand-written value that duplicates a token is a future defect. A `0.25rem` once hand-matched to daisyUI's old field radius went unnoticed until the token moved, and a soft radio card then sat above a square input in the same form. If a token already sets the value, don't type it.

**The Hairline Rule.** Borders are 1px. A boundary that needs more weight needs a different surface, not a thicker border. Weight comes from colour: ink for the rule between full-width page sections, `base-content/12` for every rule inside content and in the admin, and `base-content/20` for the admin navigation's edge. Never draw a line in `base-300`; `DesignRulesTest` enforces it.

## Components

**Character: quiet, precise, physical.** Nothing shouts, edges are exact, and the press is the one unmistakably tactile moment.

### Buttons
- **Shape:** square, no shadow, sans 500, normal case.
- **Primary:** green fill, near-white text.
- **Secondary:** green outline on the storefront; a `base-200` fill with a `base-300` edge in the admin.
- **Inverse:** a white outline over photography that fills white on hover, with a white focus ring via `--focus-color`.
- **Text:** not a button: an inline link with the static underline.

Pick the variant by the action's role, never by how loud it should feel:

| Variant | Use for | Examples |
|---|---|---|
| Primary | The one action a surface (page header, card, drawer, form) exists for. At most one per surface. | Save, Place order, Mark as delivered, Turn on |
| Secondary | Every other action. The default. | Edit, Pause, Add booking, View in store, Undo |
| Destructive | A remove, delete or reset on the page itself. In a ⋯ menu, an `actions_menu_button` with `text-error`. | Remove size, Reset calendar |
| Ghost | Cancel or dismiss beside a primary, and icon-only buttons. Never the only way to act. | Cancel, Not now |
| Text | An action inside a sentence. | Storefront inline links |
| Inverse | Over photography only. | Hero calls to action |

Size follows place: `sm` in page headers, cards and table rows; `md` for a form's submit and a drawer's footer. A submit swaps its label for a spinner after 300ms without changing width.

### Inputs / Fields
- **Style:** square, full width, 48px tall with 16px text (so iOS never zooms), label above inside one clickable `<label>`.
- **Validation:** quiet until the field has been left once, then live. Errors sit below the field and are linked with `aria-describedby`.
- **Radio card:** a square row with a `base-300` edge that turns primary with a 5% tint when checked.

### Cards / Containers
The storefront has no cards. A product card is a link, an unframed photograph on a cream ground, the name in `card-title` with the honey underline on hover, and the price. Nothing is laid over the photograph. Focus frames the whole card.

The admin groups its forms and tables in `admin-card`, a `base-100` panel with a `/12` hairline that runs edge to edge on phones. The sign-in pages centre their lone form in the same panel. Nowhere else.

### Navigation
- **Header:** a flat row of small sans links with the honey hover underline and no active state; a drawer below `xl`.
- **Category index (signature):** a vertical list of serif words, each anchored by an eyebrow numeral, the active one carrying a snapped honey underline. The reference pages' section index uses the same pattern in sans.
- **Drawers:** one open at a time.

### Signature components
- **Size picker:** three serif words, the active one underlined in honey like the category index.
- **Carousels:** Embla on phones, bleeding to the viewport edge with neighbours scaled and faded around the focused slide; a plain row from `sm` (Favourites) or `md` (customer quotes).
- **Customer quotes:** a figure, not a card. A faint flower mark, the quote in serif in its original language with the customer's own words and emojis, an italic English translation on `/en`, and the name as an eyebrow.
- **FAQ accordion:** native `<details>` separated by `/12` rules, with no box or fill.

### Named Rules

**The Press Rule.** Every pressable control lands instantly (`opacity: 0.9`, `translate: 0 1px`, no transition) and fades back over 150ms on release. No scale, ripple or colour flash.

**The Breathe-Don't-Pop Rule.** Hover underlines are always present and transparent; only their colour transitions in. Active underlines snap. Hover is an invitation; active is a fact.

**The Quiet Disconnect Rule.** While LiveView is disconnected, the page dims to 0.7 after 400ms, so brief socket flaps never show, and stops taking clicks at once. The "Connection lost" toast stays crisp. Nothing else dims the page.

## Do's and Don'ts

### Do:
- **Do** set every new storefront heading in Crimson Text, and every label, button and nav item in Open Sans.
- **Do** separate sections with a rule, and reach for `cream` or `forest` only when a section is genuinely different.
- **Do** let the radius tokens carry squareness.
- **Do** express secondary text and decoration as an existing opacity step on `base-content`.
- **Do** run photographs full-bleed and unframed, with the gradient scrim for any text over them.
- **Do** put `text-balance` on every heading.
- **Do** guard every animation with `prefers-reduced-motion: no-preference`.
- **Do** give a visually replaced control its focus ring back through `:has(input:focus-visible)`.
- **Do** recolour the focus ring with `--focus-color` when green would vanish against the surface.

### Don't:
- **Don't** let the honey accent become anything but the underline.
- **Don't** add a shadow that doesn't answer "what would the user not know without this?".
- **Don't** wrap storefront content in a card, a panel or a bordered box.
- **Don't** introduce a colour outside hue 60–80 or ~150, except admin status colours.
- **Don't** drift toward the generic florist template: no pastel pinks, script fonts, pill buttons, heart icons, soft drop shadows or stock bouquet photography.
- **Don't** bring SaaS dashboard chrome onto the storefront: no cards-in-cards, elevated panels, gradient CTAs or coloured status pills.
- **Don't** reach for luxury pastiche: no thin all-caps sans at large sizes, no black-and-gold, no borrowed-prestige letter-spacing.
- **Don't** use any radius utility but `rounded-full`, or draw a line in `base-300`.
- **Don't** hand-write a value a token already sets.
- **Don't** square `--radius-selector`.
- **Don't** transition an active state.
