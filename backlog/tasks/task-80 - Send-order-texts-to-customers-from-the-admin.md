---
id: TASK-80
title: Send order texts to customers from the admin
status: needs-triage
assignee: []
created_date: '2026-10-21 08:17'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 162000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can send a customer an SMS about their order (for example 'out for delivery' or 'ready for pickup') from the admin order page, through Brevo.

**Why:** Some customers give only a phone number, so they get no fulfilment email at all, and a text is the quickest way to reach someone about a delivery. Today Jennie texts from her own phone through the order page's SMS links.

Brevo already holds customers' numbers in E.164 in the built-in SMS attribute (SyncNewsletterList), but transactional SMS (POST /v3/transactionalSMS/sms) only needs the recipient number, so sending can use the order's customer_phone_number directly via Edenflowers.PhoneNumber.format(number, :e164).

Open:
- Free text or fixed templates per message (localised by the order's locale)?
- Manual only, or also automatic alongside the fulfilment email?
- Record sent texts on the order (sent_at, failure) like fulfillment_emailed_at?

Brevo setup (human): buy SMS credits and register the sender name (max 11 characters, e.g. Edenflowers).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The admin order page has a send-SMS action for orders with a customer phone number
- [ ] #2 The text is sent through Brevo's transactional SMS API from the configured sender name
- [ ] #3 A failed send shows an error in the admin and is logged
- [ ] #4 Brevo has SMS credits and an approved sender name
<!-- AC:END -->
