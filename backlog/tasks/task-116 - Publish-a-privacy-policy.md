---
id: TASK-116
title: Publish a privacy policy
status: needs-triage
assignee: []
created_date: '2026-10-24 19:28'
updated_date: '2026-10-26 18:57'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 237000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A privacy policy at `/{lang}/privacy` tells customers what the shop keeps about them, who it shares it with, for how long, and how to ask for it to be deleted.

**Why:** The shop stores names, addresses, phone numbers and newsletter signups, and GDPR requires a privacy notice. The site has none.

**Facts found (2026-10-24):**
- **Data kept:**
  - Orders: buyer name, email, phone, Instagram; recipient name and phone; address, delivery instructions, card message, geocoded position, delivery photo.
  - Users: name, email, newsletter opt-in and locale.
  - Course bookings: name and email.
  - Subscriptions: recipient and address details.
  - Payments: card brand and last 4 digits only.
  - Paper trail versions copy order fields.
  - Contact and wedding forms are emailed, not stored, and stay in Oban args for 7 days.
  - No IP or user-agent logging. No analytics.
- **Shared with:**
  - Stripe: payments and saved cards. Stripe.js sets cookies on the checkout and pay pages.
  - HERE: geocodes delivery addresses.
  - Brevo: transactional email and the newsletter. The nightly sync also sends customers who never opted in, with phone, order count, last order date and total spent, "so order texts can reach them".
  - Cloudflare: the tunnel all traffic comes through.
  - Mapbox: probably the admin delivery map. Unconfirmed.
  - One server at 62.238.19.203, provider not named in the repo.
- **Cookies:** the session cookie holds the cart, locale and auth, lasts 30 days, and is essential only. Stripe cookies on the payment pages. No banner needed.
- **Retention:**
  - Nothing is deleted. There is no account deletion.
  - Error records are kept forever.
  - Server backups are kept 30 days on the same host.

**Open (grilling Q20 to Q24, recommendations given, not yet answered):**
- Controller: the legal name and company form as in YTJ. Contact: info@edenflowers.fi.
- Hosting provider: whois the IP and name it, plus EU location.
- Brevo non-opted-in contacts: keep and disclose, or stop sending order totals for them? Recommended: send ORDER_COUNT, LAST_ORDER_DATE and TOTAL_SPENT only for opted-in contacts.
- Retention: orders kept for 7 years (bookkeeping law), everything else until a deletion request. Deletion by email to info@, handled by hand.
- Page names: Privacy policy / Dataskyddsbeskrivning / Tietosuojaseloste. Links in the footer beside the terms, by the checkout newsletter checkbox and by the footer signup form.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /en/privacy, /sv/privacy and /fi/privacy name the controller, the data kept, each processor, cookies, retention and how to request access or deletion
- [ ] #2 Footer, checkout newsletter checkbox and footer signup link to it
- [ ] #3 The page is in the sitemap with language alternates
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Conversation decisions: David confirmed Jennie McCrea as the legal controller and Hetzner hosting in Finland. He approved adding the policy as a clearly marked draft with retention and international-transfer details unresolved. The parent remains needs-triage, not complete publication. Current source-backed audit: docs/research/privacy-policy-data-audit.md. Its findings supersede the older description where they conflict, notably global Stripe.js loading, diagnostic IP/form-data capture, Mapbox delivery coordinates and the absence of an approved blanket seven-year retention period.

TASK-116.1 adds the approved draft page and links; it does not finish publication. Retention, transfer safeguards, remaining recipients, browser-cookie/automated-decision assessment and translations remain unresolved. Draft pages are deliberately noindex and not in the sitemap until the notice is completed.

David approved a two-week retention period for delivery photographs. Cleanup is tracked separately as a needs-triage child task; automatic deletion is not implemented by the privacy-page copy change.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 18:57

---

Legal review: docs/research/privacy-policy-legal-review.md. David requested policy copy now, technical implementation later. New needs-triage subtasks cover retention, Brevo minimisation, browser/Stripe consent and Article 14 recipient information; TASK-116.2 already owns photo expiry. Provider identity/roles, Article 28 agreements and transfer safeguards still need factual confirmation, plus a proportionate processing register, rights/breach checklist and security review. Do not treat draft/noindex as compliance or finalise publication until these gaps and customer-language notices are resolved.

---
<!-- COMMENTS:END -->
