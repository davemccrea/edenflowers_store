---
id: TASK-51
title: Send the store's email through a dedicated provider instead of Fastmail
status: ready-for-human
assignee: []
created_date: '2026-10-18 19:07'
updated_date: '2026-10-20 21:00'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: chore
ordinal: 116000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Move all email the store sends (sign-in codes, order confirmations, newsletter codes, admin alerts) off Fastmail SMTP onto a provider built for it, ideally one that can also send SMS and WhatsApp.

**Why:** Fastmail's Terms of Service say the service is not for automated or transactional email and list outbound transactional email as prohibited use. If Fastmail closes the account, customers can't sign in or get order emails, and the shop loses its inbox too.

Today `Edenflowers.Mailer` uses `Swoosh.Adapters.SMTP` with relay `smtp.fastmail.com` (config/runtime.exs). Swoosh has adapters for the usual providers, so the email code shouldn't need to change.

Open: which provider. It should:
- send transactional email with a Swoosh adapter
- also send SMS and WhatsApp, so later order or delivery notifications don't need a second provider
- ideally send one-off campaigns too, for the "we have a new website" email to recent customers of the old site (priv/heroku_import/recent_customers.exs)
- keep data in the EU, or at least have a GDPR data processing agreement

Candidates to compare on Finnish SMS/WhatsApp pricing and the free tier:
- Brevo: EU-based; email, SMS and WhatsApp; campaigns and transactional; Swoosh adapter
- Twilio (SendGrid for email): SMS and WhatsApp are its core product; US-based; SendGrid has a Swoosh adapter
- Mailgun EU region or Postmark: email only, so they'd need a separate SMS provider

Sources: https://www.fastmail.com/policies/terms-of-service/ (sections 3 and 4), https://www.fastmail.help/hc/en-us/articles/17440777620879
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A provider is chosen and recorded in this task
- [ ] #2 Production sends all store email through the new provider, not smtp.fastmail.com
- [ ] #3 SPF, DKIM and DMARC records for edenflowers.fi cover the new provider, and a test email passes all three
- [ ] #4 A sign-in code and an order confirmation arrive in a real inbox from staging and production
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Chose Brevo (2026-10-21): EU-based, transactional email and campaigns, SMS and WhatsApp, and Swoosh ships an adapter. Maileroo was considered: cheaper and SMTP-compatible, but its SMS/WhatsApp only sends verification codes.

Mailer now uses Swoosh.Adapters.Brevo with BREVO_API_KEY (prod already uses Swoosh.ApiClient.Req); gen_smtp dropped. phoenix-ansible passes BREVO_API_KEY from vault_brevo_api_key in place of the SMTP vars.

Left for a human: create the Brevo account, verify edenflowers.fi and the sender, add Brevo's DKIM/SPF/DMARC records, put vault_brevo_api_key in vault.yml for staging and production, then test real inboxes.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 21:00

---

Code side is done (Brevo adapter, phoenix-ansible vars). Left: Brevo account and domain verification, DNS records, vault_brevo_api_key in vault.yml, then deploy and check a sign-in code and order confirmation arrive (AC 2-4).

---
<!-- COMMENTS:END -->
