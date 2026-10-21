---
id: TASK-83
title: Show a spinner on every submit button while it's working
status: ready-for-agent
assignee: []
created_date: '2026-10-21 15:28'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 168000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every button that sends something (checkout steps, sign in, add to cart, newsletter, promo code, admin saves) disables and shows a spinner from the moment it's pressed until the server answers.

**Why:** On a slow connection a button that looks unchanged after a tap invites a second tap or makes the site feel broken, most of all at checkout and sign in where customers are already unsure.

## Today
`<.form_button>` in `core_components.ex` already does this: it swaps label for spinner off LiveView's `.phx-submit-loading` class, with no layout shift, a 300ms delay before the spinner shows, and a reduced-motion fallback. Only the checkout Next buttons, the Pay button and course booking use it. Every other submit is a plain `<.button type="submit">` or `<button>` (sign in, account, subscription manager, newsletter, promo code, weddings enquiry, product page, all admin forms). Some admin buttons only swap text through `phx-disable-with`.

## What to build
- Switch every `phx-submit` form's submit button to `<.form_button>`, or give `<.form_button>` the `variant`/`size` attrs it needs to stand in for `<.button>` where the look differs (admin `size="sm"` header buttons that submit with `form=`).
- `phx-click` buttons that send something (e.g. add to cart, if it isn't a form) need the same spinner off `.phx-click-loading`.
- Drop `phx-disable-with` where the spinner replaces it, so the button doesn't do both.
- Buttons outside the form they submit (`form="product-form"`) don't get `.phx-submit-loading` from a parent form. Check what LiveView puts on them and make them spin too.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every phx-submit form on the storefront, account, auth and admin pages shows the spinner and is disabled while submitting
- [ ] #2 Buttons that submit through phx-click show the same spinner while the event is in flight
- [ ] #3 Header save buttons that submit a form by id spin as well
- [ ] #4 No button uses both phx-disable-with and the spinner
- [ ] #5 A test covers that a converted button renders the spinner markup
<!-- AC:END -->
