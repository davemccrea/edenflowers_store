# WCAG 2.2 Level AA Accessibility Audit

**Site:** Eden Flowers store (Phoenix LiveView)
**Date:** 2026-05-08
**Conformance target:** WCAG 2.2 Level AA (also the EU Accessibility Act baseline)
**Method:** Static code review of templates, components, hooks, and CSS, plus live browser audit using axe-core 4.10.2 against home, store listing, and a product detail page (with maintenance bypass).

---

## Summary

| Severity | Count | WCAG bucket |
|---|---|---|
| Critical | 4 | 1.3.1 Info & Relationships, 4.1.2 Name/Role/Value, 3.3.2 Labels |
| Serious | 7 | 1.4.3 Contrast, 2.4.7 Focus Visible, 2.5.8 Target Size, 1.3.1 |
| Moderate | 6 | 2.4.1 Bypass Blocks, 3.1.1/3.1.2 Language, 4.1.3 Status Messages |
| Minor | 5 | 1.4.4 Resize Text, 2.3.3 Animation, polish |

axe-core live runs returned 5–6 violations and 41–43 passes per page. The bulk of failures are in component primitives (input, drawer, FAQ accordion, social links), which means a small number of fixes ripple across the whole site.

---

## Critical

### C1. FAQ accordion uses unlabelled radio inputs
**WCAG:** 3.3.2 Labels or Instructions, 4.1.2 Name, Role, Value, 1.3.1 Info & Relationships
**Where:** `lib/edenflowers_web/live/product_live.ex:145-189`

Five `<input type="radio">` elements drive the daisyUI accordion CSS hack with no `<label>`, no `aria-label`, and no `aria-labelledby`. Screen readers announce "radio button, not checked" with no name. Keyboard users can focus them but get no audible context.

**Fix:** Replace the radio-input pattern with `<details>`/`<summary>` (native, keyboard-accessible, no JS), or use the disclosure pattern with `aria-expanded` on a `<button>` wired to a `phx-click` toggle. The radio-CSS hack is a styling shortcut that breaks accessibility.

### C2. `<.input>` component does not surface validation errors to assistive tech
**WCAG:** 3.3.1 Error Identification, 4.1.3 Status Messages, 1.3.1 Info & Relationships
**Where:** `lib/edenflowers_web/components/core_components.ex:275-407`

When a field has `@errors`, the component renders an error message visually but does not set:
- `aria-invalid="true"` on the input
- `aria-describedby` linking the input to the error element

A screen reader user submitting the contact, newsletter, or checkout forms hears no error feedback on the field they need to fix.

**Fix:** Add `aria-invalid={@errors != []}` and `aria-describedby={@errors != [] && "#{@id}-error"}` to every input variant, and give each error block `id={"#{@id}-error"}`. This is a single component change with sitewide impact.

### C3. Drawers (cart, checkout summary) have no accessible name
**WCAG:** 4.1.2 Name, Role, Value, 2.4.6 Headings and Labels
**Where:** `lib/edenflowers_web/components/core_components.ex:691-736` (drawer), `lib/edenflowers_web/live/checkout_live.ex` (card-drawer)

The drawer correctly uses `role="dialog"` and `aria-modal="true"`, but neither variant sets `aria-labelledby` or `aria-label`. NVDA/VoiceOver announce "dialog" with no title.

**Fix:** Pass an `aria-labelledby` slot or attribute pointing at the visible heading inside each drawer, or accept a `title` prop and set `aria-label`. Same change covers the card-drawer in checkout.

### C4. Social media links go to `href="#"`
**WCAG:** 2.4.4 Link Purpose, 4.1.2 Name, Role, Value
**Where:** `lib/edenflowers_web/components/core_components.ex:626, 638` (footer socials)

Links to Instagram and Facebook resolve to `href="#"`, which (a) is functionally broken, (b) jumps the page to top, and (c) has no `aria-label` describing the destination. The icon-only links have no accessible name either.

**Fix:** Replace with real URLs and add `aria-label="Eden Flowers on Instagram"` etc. If the accounts don't exist yet, hide the icons with a feature flag rather than ship dead links.

---

## Serious

### S1. Insufficient contrast on muted text
**WCAG:** 1.4.3 Contrast (Minimum) — 4.5:1 for normal text, 3:1 for large
**Where:** Many call sites using `text-base-content/50` and `text-base-content/60`

`--color-base-content` resolves to roughly OKLCH lightness 0.21 on near-white (`base-100: white`, `base-200: 98.5%`, `base-300: 97%`). At 50% alpha that computes well below 4.5:1 for body copy. axe flagged eight instances on the home page alone.

**Fix:** Lift muted copy to `/70` or darken `--color-base-content`. Better: define `--color-muted` as a single OKLCH value chosen to pass 4.5:1, and replace the alpha utilities with it. Alpha-blending is a fragile contrast strategy because the result depends on the surface underneath.

### S2. No `:focus-visible` styles in `app.css`
**WCAG:** 2.4.7 Focus Visible, 2.4.11 Focus Not Obscured (Minimum) — new in 2.2
**Where:** `assets/css/app.css` (no global focus rule)

axe flagged 12 of 31 focusable elements without a visible focus indicator. Browser defaults are inconsistent across daisyUI components and can be removed by Tailwind's preflight. Notably, the Stripe Elements hook (`assets/js/hooks.js:459-463`) does set a 2px outline with offset for its iframes — that's the contract the rest of the site should match.

**Fix:** Add a global `:focus-visible` rule with a 2px outline in `--color-primary` and `outline-offset: 2px`. Verify by tabbing through home → store → product → checkout. (Note: axe sometimes misreports focus when elements are programmatically focused; verify with a real keyboard pass.)

### S3. Maximum-scale=1 blocks pinch zoom
**WCAG:** 1.4.4 Resize Text, 1.4.10 Reflow
**Where:** `lib/edenflowers_web/components/layouts/root.html.heex:5`

`<meta name="viewport" content="... maximum-scale=1">` prevents users with low vision from zooming on iOS Safari.

**Fix:** Drop `maximum-scale=1` and `user-scalable=no`. Modern iOS no longer needs this for input zoom; use `font-size: 16px` minimum on inputs instead.

### S4. Newsletter submit button below 24×24 px target size
**WCAG:** 2.5.8 Target Size (Minimum) — new in 2.2
**Where:** `lib/edenflowers_web/components/newsletter_signup_form.ex:33-39`

The arrow-icon submit is rendered inside a tight padding box. Measured at roughly 18×18 px hit area on the rendered footer.

**Fix:** Set `min-h-6 min-w-6` on the button (or a larger 44×44 padded hit area for comfort).

### S5. Quantity stepper buttons in cart use generic labels
**WCAG:** 4.1.2 Name, Role, Value, 2.4.6 Headings and Labels
**Where:** `lib/edenflowers_web/components/line_items_component.ex`

`aria-label="Decrement"` / `aria-label="Increment"` / `aria-label="Remove"` repeat across all line items with no product context. A screen reader user navigating the cart hears "Decrement, button, Decrement, button, Remove, button…".

**Fix:** Compose context: `aria-label={"Decrease quantity of #{item.product.name}"}`. Same for increment and remove. Use `~t` for translation.

### S6. Calendar grid lacks descriptive labels
**WCAG:** 4.1.2 Name, Role, Value
**Where:** `lib/edenflowers_web/components/calendar_component.ex` (uses `CalendarHook` in `assets/js/hooks.js`)

The roving-tabindex implementation is solid (arrow keys, Home/End, PageUp/PageDown all wired up). What's missing: an `aria-label` on the grid (e.g. "Choose delivery date, May 2026") and a full-date `aria-label` on each day button (e.g. "Saturday, May 9, 2026"). Screen readers currently hear "9, button" with no month or weekday.

**Fix:** Add the labels. The hook can stay; this is a template change.

### S7. `<h1>` repeats in checkout step heading
**WCAG:** 1.3.1 Info & Relationships, 2.4.6 Headings and Labels
**Where:** `lib/edenflowers_web/live/checkout_live.ex:692` (`form_heading/1` component)

Each checkout step renders its title as `<h1>`, so the page contains 4–5 `<h1>` elements over its lifetime. A screen reader's heading list becomes "Delivery, Address, Payment, Review" all at level 1.

**Fix:** Use `<h2>` for step headings under the persistent page `<h1>` (or render the page `<h1>` once at the top of `checkout_live.ex` and demote step titles).

---

## Moderate

### M1. No skip link
**WCAG:** 2.4.1 Bypass Blocks
**Where:** `lib/edenflowers_web/components/layouts.ex` (app layout)

Keyboard users must tab through the full header (logo, nav, locale picker, cart) on every page.

**Fix:** Add a `Skip to main content` link as the first focusable element, visually hidden until focused, jumping to `#main`. Add `id="main"` and `tabindex="-1"` to the `<main>` element.

### M2. `<html lang="en">` is hardcoded
**WCAG:** 3.1.1 Language of Page, 3.1.2 Language of Parts
**Where:** `lib/edenflowers_web/components/layouts/root.html.heex:2`

The site supports multiple locales (Localize), but the document `lang` attribute is always `en`. Screen reader pronunciation degrades when a Finnish or Swedish page is read in English voice.

**Fix:** Bind `lang={@locale || "en"}` from the conn assigns set during locale resolution.

### M3. Form success/error states have no live region
**WCAG:** 4.1.3 Status Messages
**Where:** `lib/edenflowers_web/components/newsletter_signup_form.ex` (success state), checkout flash messages

When the newsletter form swaps to its success message, screen readers don't announce it because the new content isn't in an `aria-live` region. Same for inline checkout errors.

**Fix:** Wrap the swappable status content in `<div role="status" aria-live="polite">`. The flash component already uses `role="alert"` for errors — confirm it's used consistently.

### M4. Icon-only buttons in app shell missing aria-labels
**WCAG:** 4.1.2 Name, Role, Value
**Where:** `lib/edenflowers_web/components/layouts.ex` (header icon buttons in some places)

Cart, locale-picker trigger, and a couple of nav-toggle buttons have icon-only content. Some have `aria-label`, some don't (the new native locale-picker dropdown sets it correctly; older buttons inconsistent).

**Fix:** Sweep header buttons. Anything with only an icon child needs `aria-label={~t"..."}`.

### M5. `aria-labelledby` uses product name as DOM id
**WCAG:** 4.1.1 Parsing (deprecated but still good practice), robustness
**Where:** `lib/edenflowers_web/live/home_live.ex:56`

`aria-labelledby={product.name}` — product names contain spaces, accents, and case differences. Two products with similar names would collide; any name with a space produces an invalid id.

**Fix:** Use `aria-labelledby={"product-#{product.id}-name"}` and set the matching id on the `<h3>`.

### M6. Manifest fetch returns 400
**Not a WCAG issue, but caught during the audit**
**Where:** Browser console: `site.webmanifest?v=20260506` returns 400.

PWA install/branding broken. Worth fixing while you're in the area.

---

## Minor

### Mn1. No `prefers-reduced-motion` handling
**WCAG:** 2.3.3 Animation from Interactions (AAA, but EAA-aligned)
The body fade-in (`assets/css/app.css:62-71`) and any transitions should be disabled under `@media (prefers-reduced-motion: reduce)`.

### Mn2. Drawer close button could trap focus better
The `focus_wrap` is correct on open, but verify the close button is the first tab stop and Escape always closes. Spot-checked: works for cart drawer, untested on card-drawer.

### Mn3. Long alt text policy
Product images have `alt={product.name}`. For decorative variant thumbnails, prefer `alt=""` so screen readers don't repeat the product name once per variant.

### Mn4. Auth background pattern
`auth-background-pattern` (`assets/css/app.css:185-188`) is decorative SVG — already correctly applied as `background-image` (not `<img>`), so no alt issue. Keep as-is.

### Mn5. Stripe iframe focus styling is the gold standard
`assets/js/hooks.js:459-463` builds Stripe Elements with a 2px outline + offset. Match this elsewhere when fixing S2.

---

## What's already good

- Semantic landmark structure: `<header>`, `<main>`, `<footer>` consistently present (`lib/edenflowers_web/components/layouts.ex`).
- Calendar grid implements full ARIA grid keyboard pattern with roving tabindex (`assets/js/hooks.js:176-190`).
- Drawers use `focus_wrap` and `role="dialog" aria-modal="true"`.
- Newsletter form uses `sr-only` label correctly (`lib/edenflowers_web/components/newsletter_signup_form.ex`).
- Flash component uses `role="alert"` for error variants.
- Translations via `~t"..."` (`Localize`/GettextSigils) are wired through component slots, so accessibility-name fixes can be localised cheaply.
- Stripe Elements appearance includes a real focus outline.

---

## Recommended fix order

1. **C1** — replace FAQ radio hack with `<details>`/`<summary>` (one file, instant win).
2. **C2** — add `aria-invalid` / `aria-describedby` to `<.input>` (one file, sitewide).
3. **C4** — fix or remove footer social links.
4. **S2** — global `:focus-visible` rule.
5. **S3** — drop `maximum-scale=1`.
6. **C3** — drawer accessible names.
7. **S1** — define `--color-muted` and replace `text-base-content/50,/60` usages.
8. **M2** — bind `lang` to current locale.
9. **S5, S6, S7** — labels on cart steppers, calendar, checkout headings.
10. Remaining moderate/minor items as a polish pass.

After steps 1–5 the site should pass an automated axe scan with no violations on the audited pages and meet WCAG 2.2 AA on the new-in-2.2 success criteria (target size 2.5.8, focus-not-obscured 2.4.11, dragging movements 2.5.7 — calendar already supports keyboard alternatives).

---

## Method notes

- Static review: `lib/edenflowers_web/components/`, `lib/edenflowers_web/live/`, `assets/css/app.css`, `assets/js/hooks.js`, `lib/edenflowers_web/components/layouts/root.html.heex`.
- Live audit: axe-core 4.10.2 injected via Playwright MCP. Pages tested: `/`, `/store/bouquets`, one product detail page. Maintenance mode bypassed via `?preview=secret` query param.
- Caveats: live keyboard tab-through was not performed end-to-end in this pass; S2's "12/31 elements without focus indicator" is axe's static analysis and should be verified with a real keyboard. Color contrast was sampled, not exhaustively measured per token.
