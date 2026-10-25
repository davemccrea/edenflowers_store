---
id: TASK-131
title: Send transactional email through Scaleway instead of Brevo
status: needs-triage
assignee: []
created_date: '2026-10-25 14:24'
labels:
  - spec
  - customers
dependencies: []
references:
  - 'https://help.brevo.com/hc/en-us/articles/19100260472850'
priority: medium
type: chore
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Send sign-in codes, order, payment and course emails through Scaleway Transactional Email, keeping Brevo only for the newsletter.

**Why:** Brevo adds a List-Unsubscribe header to transactional email, so mail clients like Fastmail show an Unsubscribe button on sign-in codes. A customer who clicks it lands on Brevo's transactional blocklist and silently stops getting sign-in codes and order emails. Brevo only offers a List-Help header instead on the Enterprise plan.

Findings so far:
- `Edenflowers.Mailer` uses `Swoosh.Adapters.Brevo` (`config/runtime.exs`), which posts to Brevo's transactional API (`/v3/smtp/email`). Newsletter unsubscribes are a separate Brevo blocklist and don't affect transactional mail.
- `Swoosh.Adapters.Scaleway` is in the installed Swoosh. It needs `project_id` and `secret_key`, sends from `fr-par`, supports attachments (receipt PDFs, delivery photo) and drops `reply_to`. Nothing in `lib/` sets a reply-to today.
- `BREVO_API_KEY` stays: `SyncNewsletterList` still needs it.
- Prod env vars come from `infra/roles/common/templates/docker-compose.yml.j2`, `infra/group_vars/all/vars.yml` and `infra/vault.example.yml`.

Open questions:
- Does Scaleway add a List-Unsubscribe header to transactional mail? Check the headers of a test email in Fastmail before committing to it.
- Is Scaleway's starting daily sending quota enough for the shop's volume?
- Should the shop's wedding enquiry email set Reply-To to the customer? If so, it has to go through `additional_headers`, because the adapter drops `reply_to`.

Human steps: create the Scaleway project, add edenflowers.fi under Transactional Email, publish its SPF/DKIM/DMARC records, wait for verification, create an API key and add the project ID and secret key to the vault.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Prod sends all transactional email through Scaleway; Brevo is used only for the newsletter list
- [ ] #2 A sign-in code email received in Fastmail shows no Unsubscribe button
- [ ] #3 SPF, DKIM and DMARC pass for edenflowers.fi on Scaleway-sent mail
- [ ] #4 Receipt PDF and delivery photo attachments arrive intact
<!-- AC:END -->
