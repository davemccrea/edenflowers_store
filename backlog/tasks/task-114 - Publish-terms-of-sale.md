---
id: TASK-114
title: Publish terms of sale
status: done
assignee: []
created_date: '2026-10-24 19:27'
updated_date: '2026-10-26 19:21'
labels:
  - spec
  - customers
  - admin
dependencies:
  - TASK-113
priority: medium
type: feature
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A short Terms of sale page at `/{lang}/terms` sets out the shop rules on delivery, substitution, cancellation, quality and invoices.

**Why:** These rules were in the old store PDF and appear nowhere on the new site. When a delivery cannot get in or a flower is swapped, neither the customer nor Jennie has anything to point to.

Decided in grilling (2026-10-24). Keep it to the main points and leave out any consumer-law text except the one withdrawal sentence. In order:
1. **Seller:** Eden Flowers, Business ID, address, email and phone, read from `EdenflowersWeb.Business`.
2. **Prices and payment:** prices include VAT (no rate). Checkout accepts MobilePay, card, Apple Pay and Google Pay. Subscriptions charge the saved card.
3. **Delivery and pickup:**
   - Delivery is within the delivery option max distance (20 km, read live) on the day chosen at checkout from the shop calendar. There are no time slots.
   - Pickup: the customer picks a date and gets a message when the order is ready. They collect it during opening hours, or contact Jennie for another time.
   - The customer makes sure Jennie can get in: a door code in the delivery instructions, or the recipient at home.
   - No way in: the order goes back to the shop to be picked up, or the customer pays for another delivery.
   - Nobody home: it is left at the door and the customer is emailed a photo of where.
   - Wrong address or recipient details: not refunded.
4. **Substitution:** if a flower is out of season or the wholesalers do not have it, Jennie may replace it with something similar of the same value.
5. **Cancellation:**
   - Online orders: from the account until 3 days before (read from the TASK-113 constant). Otherwise contact Jennie.
   - Courses: the terms on each course page.
   - Weddings: the booking-fee rule from the weddings page (half is invoiced about 4 weeks before and is not refunded after that).
   - One sentence: flowers are made to order and perishable, so the 14-day withdrawal right does not apply.
6. **Quality:** damaged or wilting flowers are replaced or refunded if reported within 4 days of delivery, provided they were cared for (fresh water and so on). Send Jennie a photo.
7. **Invoices:** offered to businesses and larger orders such as weddings. Due as stated on the invoice. Late payment adds interest under the Interest Act (korkolaki) plus 5 euros for each reminder.

**Page details:**
- Names: Terms of sale / Köpvillkor / Toimitusehdot.
- Style: one heading per section, styled like the FAQ, in Jennie first-person voice.
- Links: the footer Help list (layouts.ex:864-891), and a line in the stripe_form `before_button` slot at checkout (checkout_live.ex:318), "By placing your order you accept the terms of sale". Add the page to the sitemap with alternates.
- Translations: draft sv and fi. Jennie Swedish becomes the master text later (see the Swedish review spec).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /en/terms, /sv/terms and /fi/terms show the seven sections, with distance and cancellation days read live
- [x] #2 The footer and the checkout pay step link to the terms
- [x] #3 The page is in the sitemap with language alternates
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Page at TermsLive with seven sections; delivery max_dist_km and change_deadline_days read live. Localized slugs like every other page: /sv/kopvillkor, /fi/toimitusehdot. Business ID moved into EdenflowersWeb.Business (footer reads it too). Checkout line opens the terms in a new tab so the Stripe form isn't lost. sv/fi are drafts for TASK-117.

2026-10-26 copy review: terms now group general purchase rules before service-specific terms, use the shared FAQ section index and reading styles, and link contact invitations to the Contact page. Quality concerns should be reported as soon as possible with a photo, replacing the earlier fixed reporting window. Delivery availability is product-dependent and shown at checkout; midday is only the usual same-day cutoff. Added Stripe processing and full-card-number/security-code storage wording. English, Swedish and Finnish are aligned; TASK-117 remains the separate human Swedish review.

Validation: compile with warnings as errors, Ash codegen check, unused-dependency check, formatting, strict Credo, Gettext freshness and all 1,702 tests pass. Desktop and mobile browser checks cover the delivery checker and shared section navigation. Full mix precommit is blocked at its existing critical dependency-audit gate by hackney 4.8.7 (EEF-CVE-2026-115693); dependency updates are outside this copy/UI change.

Requested presentation follow-up: use restrained sans-serif page/section headings and sidebar links for Terms, with normal body-text colour rather than 80% opacity. SectionIndex has an opt-in sans variant; FAQ keeps its existing serif style. No terms wording or last-updated date changed. Verification: 55 focused privacy/terms/localized-page/FAQ tests passed, targeted format check, Tailwind build and git diff --check passed.

Added Updated 26 October 2026 beneath the Terms title, matching the Privacy notice wording, muted date styling and spacing. The date is fixed to this substantive terms revision rather than computed at runtime. Added a date-placement regression test. Verification: focused Terms/Privacy tests and git diff --check passed; formatting applied. No translations generated.

Added a separate Related information group beneath the Terms section index linking to localised FAQ and Privacy routes. Shared sidebar sticks as a group on desktop; related links remain visible on mobile while in-page navigation stays hidden. Related links are outside the section-index hook so active-section tracking is unchanged. Verification: 58 focused FAQ/Terms/Privacy/localized-page tests passed (all nine language/page combinations), assets build and git diff --check passed. New heading remains translatable; translations were not generated.
<!-- SECTION:NOTES:END -->
