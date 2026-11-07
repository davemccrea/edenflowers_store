---
id: TASK-131
title: Send transactional email through Scaleway instead of Brevo
status: done
assignee: []
created_date: '2026-10-25 14:24'
updated_date: '2026-11-07 08:19'
labels:
  - spec
  - customers
dependencies: []
references:
  - 'https://help.brevo.com/hc/en-us/articles/19100260472850'
priority: low
type: chore
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Send sign-in codes, order, payment and course emails through Scaleway Transactional Email instead of Brevo.

**Why:** Brevo adds a List-Unsubscribe header to transactional email, so mail clients like Fastmail show an Unsubscribe button on sign-in codes. A customer who clicks it lands on Brevo's transactional blocklist and silently stops getting sign-in codes and order emails. Brevo only offers a List-Help header instead on the Enterprise plan. With the newsletter moving to MailerLite (TASK-157), Brevo can then be cancelled.

Findings:
- `Swoosh.Adapters.Scaleway` is in the installed Swoosh. It needs `project_id` and `secret_key`, sends from `fr-par`, supports bcc and attachments, and drops `reply_to`. Nothing sets a reply-to.
- Pricing: 300 emails a month free, then about 0.25 EUR per 1000.
- Scaleway forbids marketing email on this service, so the newsletter can't go through it.
- Prod env vars come from `infra/roles/common/templates/docker-compose.yml.j2`, `infra/group_vars/all/vars.yml` and `infra/vault.example.yml`.

Open (human checks):
- Does Scaleway add a List-Unsubscribe header to transactional mail? Check a test email in Fastmail.
- Is the starting sending quota enough for the shop's volume?

Human steps: create the Scaleway project, add edenflowers.fi under Transactional Email, publish its SPF/DKIM/DMARC records, wait for verification, create an API key and add the project ID and secret key to the vault.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sign-in code email received in Fastmail shows no Unsubscribe button
- [x] #2 SPF, DKIM and DMARC pass for edenflowers.fi on Scaleway-sent mail
- [x] #3 Receipt PDF and delivery photo attachments arrive intact
- [x] #4 Prod sends all transactional email through Scaleway; Brevo is not used
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:58

---

Launch triage 2026-10-27 with David: after launch, not a blocker. The unsubscribe-on-sign-in-code risk is real but rare.

---

author: @claude
created: 2026-10-31 12:49

---

Grilled 2026-10-31 with David alongside TASK-157 (MailerLite newsletter): Brevo is dropped entirely, so AC #1 now reads Brevo is not used. No Reply-To change: enquiry emails go to the customer with Jennie in bcc, so a Reply-To would point the customer's own replies at themselves. BREVO_API_KEY and BREVO_NEWSLETTER_LIST_ID stay in the compose file until Brevo is cancelled, so just rollback to an older release still boots. Ships in one deploy with TASK-157. Human steps unchanged, plus: check a delivery photo and receipt PDF arrive (Scaleway restricts attachment types).

---

author: @claude
created: 2026-10-31 12:57

---

Code done on branch mailerlite (not merged). Left for David: Scaleway project, domain records, vault_scaleway_project_id and vault_scaleway_secret_key, then check AC 1 to 3 on a test send before merging.

---

author: @claude
created: 2026-10-31 13:24

---

DNS 2026-10-31: SPF on edenflowers.fi now includes _spf.tem.scaleway.com alongside Fastmail. Still to do: the Scaleway DKIM TXT record (Scaleway shows it once edenflowers.fi is added to the project). After cutover and once Brevo is cancelled, delete the Brevo records in Cloudflare: brevo1/brevo2._domainkey CNAMEs, the brevo-code TXT, the mail, img.mail and r.mail CNAMEs (link tracking and images in emails Brevo already sent stop working), and point the DMARC rua away from rua@dmarc.brevo.com.

---

author: @claude
created: 2026-10-31 17:53

---

2026-10-31: weighed MailerSend (same company as MailerLite, about 5.64 EUR a month, nicer activity log) against Scaleway; David chose Scaleway for cost, as it is free at the shop's volume.

---

author: @claude
created: 2026-10-31 19:07

---

David chose to remove Brevo from infra entirely (compose, vars, vault example) instead of keeping BREVO_API_KEY for rollbacks. Main's vault already has vault_scaleway_project_id, vault_scaleway_secret_key and vault_mailerlite_api_key, and no Brevo key.

---

author: @claude
created: 2026-11-07 08:19

---

Merged and live since v1.23.4. David confirmed the human checks on 2026-11-07.

---
<!-- COMMENTS:END -->
