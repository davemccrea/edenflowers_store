---
id: TASK-115
title: Rewrite the FAQ around what customers ask
status: done
assignee: []
created_date: '2026-10-24 19:27'
updated_date: '2026-10-26 19:16'
labels:
  - spec
  - customers
  - admin
dependencies:
  - TASK-113
  - TASK-114
priority: medium
type: feature
ordinal: 236000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The FAQ answers the questions people actually send Jennie, grouped into sections, every answer true to the code, and marked up as FAQPage structured data.

**Why:** Fewer messages to Jennie asking things the site could answer. Some current answers are also wrong: card messages are not all up to 200 characters, and "a note with redelivery instructions" never happens.

Decided in grilling (2026-10-24). The main goal is fewer questions, in the tone of a reassuring pre-purchase page. Read numbers live wherever the code has them. Link to /terms where a rule sits behind the answer. Use the copywriting skill for the copy and the schema/ai-seo skills for the JSON-LD, emitted through the existing ld+json slot in layouts.ex:33. Gift cards are left out until they exist.

Sections and questions:
- **Ordering**
  - Can I order something that isn't in the store? Yes, contact Jennie and she will make it to order.
  - Can I add a card with a message? Yes, on gifts, by adding a card at checkout. Name the sizes and their character limits from the card sizes, read live.
  - Can I cancel an order I made online? From your account until 3 days before (TASK-113 constant). Otherwise get in touch.
- **Delivery & pickup**
  - Where do you deliver? Within the max distance (20 km), fee formula read live as `pickup_answer/0` does today. Weddings further away are quoted separately.
  - Do you deliver to hospitals? Yes, to the ward if the ward allows flowers. Check with the ward first, and put the patient name and ward in the delivery instructions.
  - What if nobody's home? I leave it at the door and email you a photo of where. Link the terms for when I cannot get in.
  - Will I know when it's delivered? Gifts: you are emailed when it is delivered. Nobody home: the left-at-the-door email with its photo (TASK-105.7 defaults).
  - Where and when can I pick up? At Minimossen (address from Business). Choose the date at checkout, you get a message when it is ready, collect it during opening hours (read live from Business), or contact Jennie for another time.
- **Flowers & care**
  - How long will my flowers last? Keep the existing 5 to 7 days and the care tips.
  - Are your flowers local and seasonal? Local and seasonal where possible. Link the terms on substitution.
  - What if they arrive damaged or wilt early? Replaced or refunded within 4 days, with proper care. Send a photo.
- **Payment**
  - Which payment methods can I use? MobilePay, card, Apple Pay and Google Pay. Subscriptions are card only. Check the Stripe dashboard for which methods are actually enabled.
  - Do prices include VAT? Yes.
  - Can businesses pay by invoice? Yes, for businesses and larger orders. Get in touch.
- **Subscriptions:** keep `subscription_questions/0`, which the product page also uses, with the TASK-113 days.
- **Weddings**
  - How far ahead should I book? The sooner the better, as the calendar fills up quickly.
  - Do you travel outside Vaasa? Yes, quoted separately.
  - How does payment work? Half is invoiced as a booking fee about 4 weeks before and the rest afterwards. Link /weddings.
- **Courses**
  - How do I cancel? Reply to your confirmation email.
  - Will I get my money back? Per each course page.
  - What's included and what should I bring? Everything is on each course page.
  - Can I book a private group? Yes, at Minimossen or at your premises. Link /courses.

The side nav lists every section. Draft sv and fi. Jennie Swedish becomes the master text later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The FAQ has the seven sections and the questions listed, with numbers read live
- [x] #2 The card message and not-home answers match what checkout and the delivery emails actually do
- [x] #3 The page emits FAQPage JSON-LD that validates
- [x] #4 faq_live_test covers the live-read answers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Answers are blocks (paragraphs, lists, links) and one list feeds both the page and the FAQPage JSON-LD; links stay out of the JSON-LD text. Card sizes and prices come from the card drawer variants, limits from ProductVariantSize. The same-day/next-day sentence from the old delivery answer now sits in 'Where do you deliver?'. Card size names come from CardDrawer.size_label/1, now public. Check the Stripe dashboard for which payment methods are really enabled.

2026-10-26 customer copy review supersedes the earlier card-limit, lifespan and reporting-window details: cards are added at checkout without character counts; flowers typically last 7–10 days depending on the flowers; quality issues should be reported as soon as possible with a photo. Added an address-based delivery-cost checker using checkout pricing, activated by Check or Enter, with an accessible unlabelled field, green price and no duplicate free-delivery result. Preserve native accordion state and focus outlines during updates. Availability depends on products and checkout dates; midday is the usual same-day cutoff. Pickup is always free; subscription answers no longer repeat delivery pricing. Wedding copy explains limited Saturday capacity and typical 9–12-month advance booking. Removed the course-inclusions question and wedding information link; contact invitations go to the Contact page. All three languages updated.

Validation: compile with warnings as errors, Ash codegen check, unused-dependency check, formatting, strict Credo, Gettext freshness and all 1,702 tests pass. Desktop and mobile browser checks cover the delivery checker and shared section navigation. Full mix precommit is blocked at its existing critical dependency-audit gate by hackney 4.8.7 (EEF-CVE-2026-115693); dependency updates are outside this copy/UI change.

User-approved visual follow-up: FAQ now matches Terms/Privacy with restrained sans-serif page, section and contact-prompt headings, sans-serif sidebar links and normal answer-text colour instead of 80% opacity. No update date added. Copy, accordion behaviour and FAQ structured data remain unchanged. Added typography/date-absence assertions for all three language routes and aligned the Terms navigation test. Verification: 57 focused FAQ/Terms/Privacy/localized-page tests passed, Tailwind build and git diff --check passed; formatting applied.
<!-- SECTION:NOTES:END -->
