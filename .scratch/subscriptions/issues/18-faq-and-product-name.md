# Fix the FAQ and rename "Weekly bouquet"

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit item B5 and the product-name decision in `10-ux-audit.md`.

## Acceptance criteria

- [x] **B5.** The FAQ answer (`faq_live.ex:29`) says: every 1, 2 or 4 weeks; free delivery within 5 km; charged 3 days before each delivery; skip, pause or cancel from your account. No 10% discount claim. Translated (sv, fi).
- [x] The "Weekly bouquet" product is renamed in seeds, with fi and sv translations.

## Blocked by

None. Needs the new product name from Jennie (FAQ part can ship without it).

## Comments

**Built (slice 18)**

- FAQ answer rewritten, with the km from `Fulfillment.free_dist_km/0` and the days from `Subscription.lead_days/0`. fi/sv translated.
- Seeded product renamed to "Florist's choice bouquet" (fi "Floristin valinta", sv "Floristens val"), following the audit's suggestion. Existing databases aren't touched: rename it in admin, or reseed.
