---
id: TASK-152
title: Send a reopening email to recent customers
status: ready-for-human
assignee: []
created_date: '2026-10-31 07:39'
updated_date: '2026-11-07 08:19'
labels:
  - spec
  - customers
  - admin
dependencies:
  - TASK-153
references:
  - >-
    https://help.brevo.com/hc/en-us/articles/34009382005138-Send-email-campaigns-in-multiple-languages
priority: medium
type: task
ordinal: 288000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie emails recent customers once to say she is back from maternity leave, the shop is open again and it has a new website, inviting them to subscribe to the newsletter.

**Why:** The shop was closed for months and the previous website had no newsletter, so past customers have no way of knowing it reopened. One letter from Jennie brings them back and gives the newsletter its first real subscribers.

Legal basis (2026-10-30/31)
- Not a newsletter, but legally marketing. Sent without consent under the existing-customer rule (Electronic Communications Services Act s. 200): own customers, similar products, a free opt-out in every message. Not legal advice; check whether the old website gave customers a chance to object when it collected their address.
- Recent customers only (roughly the last year or two), one email, no follow-ups. Recipients are not added to the newsletter; only those who subscribe through the link join it.

Tool and email (MailerLite, re-grilled 2026-11-01; Brevo is gone)
- Campaign reopening-2026 (draft) to the Reopening group (293 contacts, imported from the old Brevo list). The nightly sync manages only the Newsletter group, so it leaves the Reopening group alone.
- Swedish first, then Finnish, in one email, du/sinä. Footer kept as drafted, including "Avregistrera dig / En halua enää viestejä" and MailerLite's {$unsubscribe} link.
- Newsletter buttons link to /sv?email=…#newsletter (and /fi), which pre-fills the footer signup.

Sending (re-grilled 2026-11-01)
1. Jennie's review: MailerLite sends her a test of the real email. She replies with changes, applied in MailerLite.
2. Send date: set once she approves. The 25% offer runs two weeks from sending, so "Gäller till och med 16.11.2026" and "Voimassa 16.11.2026 asti" change to the real end date. The Instagram launch (TASK-162.1) goes out the same day.
3. Discount: David sets the welcome percent to 25% just before sending and back to 15% the morning after the offer ends (calendar reminders).
4. Clean-up, the day after the offer ends: delete the Reopening group's contacts from MailerLite, except unsubscribers (kept so they're never emailed again) and new newsletter subscribers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie has approved the Swedish and Finnish copy
- [x] #2 The campaign is sent to a temporary list of recent customers only
- [ ] #3 The welcome percent is 25% while the offer runs and back to 15% after
- [ ] #4 After clean-up, MailerLite holds only newsletter subscribers and unsubscribers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Newsletter buttons in campaign 3 link to /sv?email={{ contact.EMAIL }}#newsletter (and /fi). The homepage pre-fills the footer signup from ?email= (spaces turned back into +, since Brevo doesn't URL-encode), and Umami's data-before-send strips email= from the URL and referrer. Deploy before sending.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-31 08:53

---

The reopening email will offer 25% for two weeks after sending, set up through TASK-153. Once the send date is known, update campaign 3 to 25% with the end date. Draft refined 2026-10-31: sender, subject, newsletter button with pre-filled email, weekly bouquet paragraph, reply invite, style matched to the site.

---

author: @claude
created: 2026-10-31 19:53

---

2026-10-31: Brevo is removed (TASK-131, TASK-157, v1.23.4). The Brevo decisions above no longer hold: the campaign has to be rebuilt in MailerLite (merge tags, unsubscribe link, temporary group of recent customers). The Brevo list (294 contacts) and draft campaign 3 were downloaded to tmp/brevo-reopening/ in the main checkout before the account was closed. Re-grill the tool decisions before sending.

---

author: @claude
created: 2026-10-31 20:27

---

2026-10-31: MailerLite now holds other groups safely: the sync only manages the Newsletter group (TASK-157). Once that deploys, the 294 contacts in tmp/brevo-reopening/contacts.csv (main checkout) can be imported into a Reopening group. Still to re-grill: campaign rebuild in MailerLite, send date, clean-up after sending.

---

author: @claude
created: 2026-11-01 16:01

---

Re-grilled for MailerLite, round 1 (2026-11-01):
- Send date: set once Jennie has approved the copy. The 25% offer runs two weeks from sending, so the draft's 16.11 changes to match. The Instagram launch post (TASK-162.1) goes out the same day.
- Privacy policy: a one-off line about this single letter to customers of the previous website, and the MailerLite line adjusted to match. Deployed before sending.
- Address: keep du/sinä. An email is a letter to one person, and it matches the newsletter strings. Jennie may still change it.
- Clean-up: the day after the offer ends, delete the Reopening group's contacts from MailerLite, except unsubscribers (kept so they're never emailed again) and new newsletter subscribers.

---

author: @claude
created: 2026-11-01 16:05

---

2026-11-01: Re-grilled and agreed with David. No privacy policy change after all (David's call). Left: Jennie's test-email review, setting the date and offer end, the discount switches, sending and the clean-up.

---

author: @claude
created: 2026-11-07 08:19

---

Sent 3.11.2026; the 25% offer ends 16.11. Left: set the welcome percent back to 15% on 17.11 (AC 3) and the MailerLite clean-up the same day (AC 4).

---
<!-- COMMENTS:END -->
