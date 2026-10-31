---
id: TASK-157
title: Send the newsletter from MailerLite instead of Brevo
status: ready-for-human
assignee: []
created_date: '2026-10-31 12:48'
updated_date: '2026-10-31 20:27'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 292000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Newsletter subscribers live in MailerLite, kept in step with the site's opt-ins, so Jennie can write campaigns there and Brevo can be cancelled.

**Why:** Brevo is being dropped (transactional mail moves to Scaleway in TASK-131), and MailerLite is where Jennie wants to run campaigns.

Decisions (2026-10-31):
- The site owns consent. Every opt-in change on the site (footer, checkout, account toggle) is pushed to MailerLite at once: opting in upserts the subscriber as active with resubscribe: true, opting out marks them unsubscribed. So a new opt-in always beats an older unsubscribe.
- No group: MailerLite's active subscribers are the list; campaigns go to all active subscribers.
- The nightly sync keeps three jobs: subscribers unsubscribed in MailerLite but opted in on the site are opted out on the site; active subscribers who aren't opted in on the site (missed pushes, contacts added by hand) are marked unsubscribed; everyone else gets their fields refreshed.
- The push job and the sync share a newsletter queue that runs one job at a time, so a sync can't undo an opt-in that lands mid-run.
- Fields as Brevo had: name, last_name, phone (from the latest order), plus custom fields language (text), order_count and total_spent (number), last_order_date (date). Create the custom fields in MailerLite before go-live.
- No Brevo export: one last nightly Brevo sync before the deploy, then the first MailerLite sync fills MailerLite from the site.
- Once a night is enough; MailerLite stops campaigns at once on unsubscribe, the site just lags a day.
- Ships in one deploy with TASK-131. Cancel Brevo after a clean week.

Human steps: create the MailerLite account and custom fields, add the API key to the vault, and check on a throwaway address that an unsubscribed subscriber can be resubscribed through the API (the docs contradict themselves).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Opting in or out on the site reaches MailerLite within a minute
- [ ] #2 Someone who unsubscribes from a campaign is shown as not subscribed on the site after the next nightly sync
- [ ] #3 Someone who unsubscribed and opts in again on the site is active in MailerLite
- [ ] #4 Customers who never opted in are not sent to MailerLite
- [ ] #5 The privacy policy names MailerLite for the newsletter and Scaleway for email, in en, sv and fi
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-31 12:57

---

Code done on branch mailerlite (not merged). Left for David: create the MailerLite account and custom fields language (text), order_count and total_spent (number), last_order_date (date); add vault_mailerlite_api_key; resubscribe a throwaway address through the API to confirm resubscribe: true works; deploy right after a nightly Brevo sync, together with TASK-131.

---

author: @claude
created: 2026-10-31 20:27

---

2026-10-31: Decision changed: the site now owns a MailerLite group, Newsletter (id 202876690108515964, created), instead of all active subscribers. Pushes and the nightly field refresh add subscribers to it; the nightly sync takes members the site hasn't opted in out of the group rather than unsubscribing them, and never touches contacts outside it. Unsubscribes stay account-wide. Campaigns go to the Newsletter group. Lets other groups (the TASK-152 reopening list) live in MailerLite.

---
<!-- COMMENTS:END -->
