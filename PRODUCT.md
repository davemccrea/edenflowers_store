# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Three audiences, all confirmed as priorities for design work:

1. **Local customers ordering online** — people in Vaasa and Korsholm buying flowers for a birthday, a christening, an apology, a funeral, or their own table. They arrive knowing the occasion, not the flower. They choose a product, a delivery or pickup date, and a card message, and they pay. Many are on a phone, some in a hurry, and a real portion of the orders carry emotional weight.
2. **Wedding and event enquirers** — couples and organisers who research before they talk. Long consideration, high value, and the funnel ends in a quote request and a conversation, not a cart. Evaluated on photographs of past work.
3. **Course students** — people booking a seat on a floristry course. The domain (`Edenflowers.Courses`, registrations, capacity) exists; `/courses` is still a bare stub page.

Jennie, the owner, is the sole operator behind the admin surfaces (orders, fulfillment calendar, expenses). She was not named a design priority in this round.

## Product Purpose

Eden Flowers is a florist in Vaasa, Finland, run single-handedly by Jennie since 2018 from a shop in Minimossen, the recycling mall at Myrvägen 1. The site is the shop's storefront and its booking desk: it sells arrangements online with delivery or in-store pickup, takes wedding and event enquiries, lists courses, and runs the back office that fulfils the orders.

Success is an order placed without a phone call, and a wedding enquiry that arrives already knowing what Jennie's work looks like.

## Positioning

**The arrangements themselves.** Eden Flowers competes on the quality of the flowers as designed objects, and the site's job is to prove that with photography rather than argue it with adjectives.

The home page currently also claims "we keep our delivery rates among the lowest in Vaasa." Price is not the position; that line pulls against the confirmed one and is a candidate for removal rather than something future work must preserve.

## Operating Context

- **Place:** a physical shop inside a recycling mall, selling ready-made bouquets, houseplants and second-hand pots and vases alongside made-to-order work. Walk-in and online are the same business.
- **Region:** Vaasa and Korsholm. Delivery is distance-priced from the shop; funeral flowers are delivered to churches and chapels in both municipalities.
- **Languages:** Swedish, Finnish and English. Ostrobothnia is genuinely bilingual — a page that works only in English is broken for most of the actual customer base. Locale is negotiated from session then `Accept-Language`, defaulting to `en-GB`.
- **Occasions drive demand:** Valentine's / Friend's Day (14 Feb), Women's Day (8 Mar), Mother's Day (2nd Sunday in May), Father's Day (2nd Sunday in November) are coded as key dates and spike both the storefront and the fulfillment calendar.
- **Current state:** the shop is closed for maternity leave. A maintenance plug redirects all traffic to `/maternity`, a bilingual sv/fi holding page pointing large-event enquiries at info@edenflowers.fi. This is a temporary operating state, not the product.
- **Shop hours:** Mon–Fri 09:00–17:00, Sat 10:00–15:00.
- **Contact:** info@edenflowers.fi, +358 40 220 9494, Myrvägen 1, 65230 Vasa.

## Capabilities and Constraints

Confirmed and shipping:

- Catalogue with categories, products, variants and sizes; cart and checkout; Stripe payment with order finalisation on `payment_intent.succeeded`.
- Fulfillment options: home delivery (distance-priced) and in-store pickup, with per-product availability, weekday rules and a date picker at checkout.
- Accounts via one-time-code sign-in and Google OAuth; promotions and tax rates (Finnish VAT); course registrations; admin dashboard, order detail, fulfillment calendar and expenses.
- Expense capture: a document tagged `receipt` in Papra fires a webhook and Claude extracts the expense.
- Images are served through imgproxy; the `images/` tree is gitignored and synced to servers on deploy.

Confirmed product promises (stated by the owner; preserve these):

- **Same-day delivery** for weekday orders placed before 14:00; weekend deliveries need a Friday 14:00 order.
- **Subscriptions** — weekly, bi-weekly and monthly, with 10% off for subscribers. *No subscription code exists in the repository.* The promise is real; the implementation is not there yet.
- **Card message** with the delivery, up to 200 characters.

Explicitly NOT a product fact:

- The FAQ's "if you're not home, flowers are left in a safe shaded spot / a redelivery note is left" answer was not confirmed. Do not treat it as policy, and do not build on it.

Open / undecided:

- What the courses page actually offers (schedule, price, capacity, who they are for) is not yet decided.
- Whether the "lowest delivery rates in Vaasa" claim stays at all.

## Brand Commitments

- **Name:** Eden Flowers. Written in first person by Jennie — "Hi, I'm Jennie", "I make flowers for every occasion". The voice is one person talking, warm and plain, never a brand-we.
- **Logos:** two lockups (`logo1` stacked, `logo2` horizontal) in green, black, white and full colour, at `images/Eden_flowers-logo*.svg`. Green is the primary mark.
- **Typefaces:** Crimson Text (serif, display) and Open Sans (sans, body), both self-hosted, SIL OFL 1.1.
- Third-party photographers are credited by name on the weddings page. Credit lines are a commitment, not decoration.

## Evidence on Hand

- **Real wedding photography** in `images/wedding/`, credited to Anna Riska, Björn Yrjans, Daniela Streng, Josefin Westin, Julia Lillqvist, Maria Sundelin, Marie Lillhannus, Sara Björkskog, and Eden Flowers itself.
- **Real B2B clients**, already shown as a "Trusted by" row on the home page with live links: Dermosil, SFP/RKP (Swedish People's Party of Finland), the Evangelical Lutheran Church of Finland, and Bonnier News Finland.
- **Portraits of Jennie** (`jennie_99.jpg`, `jennie_pregnant.jpg`) and shop/product photography (`image_1.jpg`, `image_4.jpg`, `image_5.jpg`).
- **Absences future work must not fill with invention:** there are no customer testimonials, no reviews, no press quotes, no awards, no order volumes and no ratings. The condolences tile on the home page is still a placehold.co placeholder and needs a real photograph. Wedding prices on the weddings page are starting prices only.

## Product Principles

1. **Show the flowers, don't describe them.** The position is design quality, so photography carries the argument and copy stays out of its way.
2. **One person's voice.** Everything reads as Jennie speaking. No corporate plural, no invented social proof.
3. **Ordering must be easier than phoning.** Every step from product to paid order is judged against picking up the phone instead.
4. **Bilingual by default, not as an afterthought.** Swedish and Finnish are first-class; layouts must survive the longer strings.
5. **Local is the whole market.** Vaasa and Korsholm. Distance, delivery windows and the shop's own hours are real constraints, not edge cases.

## Accessibility & Inclusion

No product-specific standard has been set beyond ordinary good practice. Two real needs are established by the audience: bilingual sv/fi/en parity, and a checkout that works on a phone, since funeral and last-minute orders are frequently placed on one.
