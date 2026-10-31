---
id: TASK-152
title: Send a reopening email to recent customers
status: needs-triage
assignee: []
created_date: '2026-10-31 07:39'
updated_date: '2026-10-31 08:56'
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

Decisions (2026-10-30/31):

Legal basis
- Not a newsletter, but legally marketing. Sent without consent under the existing-customer rule (Electronic Communications Services Act s. 200): own customers, similar products, a free opt-out in every message. Not legal advice; check whether the old website gave customers a chance to object when it collected their address.
- Recent customers only (roughly the last year or two), one email, no follow-ups. Recipients are not added to the newsletter list; only those who subscribe through the link join it.
- Keep Brevo's unsubscribe link: the law needs an opt-out, Brevo requires it, and a click blocklists the contact so the newsletter sync respects it.

Tool
- Brevo stays the newsletter tool (EU-hosted, already under the privacy policy, sync built, Jennie can send herself). Marketing must not go through the app's transactional mailer. TASK-131 may move transactional email off Brevo; that doesn't change this.
- Free plan: about 300 emails a day and probably a Brevo badge in the footer.
- Brevo's multi-language campaigns need Professional plus an add-on, or Enterprise. Not worth it: send sv/fi in one email now, and target newsletters by the LANGUAGE attribute (sv-FI, fi, en-GB) with one campaign per language segment.
- Access: a Brevo MCP key in the local .env (as BREVO_API_KEY, which only prod config reads; rename to BREVO_MCP_KEY). Agents call https://mcp.brevo.com/v1/brevo/mcp with it.

Email style (Brevo template 2, "Newsletter letter (en)")
- A plain-looking letter rather than a designed newsletter: no images or header, paper background #fdfbf9, Open Sans 16px throughout (signature included), green #294735 links with the 2px honey #e2be36 underline, one square green primary button for the main action.
- Footer: EDEN FLOWERS eyebrow, Myrvägen 1, 65230 Vasa, a site link (plus In English in the sv/fi email), then why they got it and the unsubscribe link. No socials, no Finnish address.

This email (Brevo campaign 3, draft, no recipients)
- Swedish first, then Finnish, in one email. du/sinä, matching the existing newsletter strings.
- Mentions maternity leave briefly: "Efter mammaledigheten" / "Äitiysloman jälkeen".
- Leads with the new website and Jennie's excitement about it; the button ("Till webbplatsen" / "Verkkosivuille") goes to the site. Newsletter invite with the 15% code, then "otherwise you won't hear from me again".
- Subject: "Eden Flowers är öppet igen · Eden Flowers on taas auki".

Open before sending
- Jennie reviews all sv/fi copy (agent-written), including du vs ni and the unsubscribe wording ("Avregistrera dig" / "Peru viestit" suggest a sign-up; consider "Vill du inte få fler e-postmeddelanden?").
- Privacy policy line about occasional emails to past customers; it currently says Brevo holds newsletter subscribers only.
- Build a temporary Brevo list of recent customers (email, FIRSTNAME), send, then delete those contacts except unsubscribers (keep the blocklist) and new subscribers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie has approved the Swedish and Finnish copy
- [ ] #2 The privacy policy covers emailing past customers
- [ ] #3 The campaign is sent to a temporary list of recent customers only
- [ ] #4 After sending, Brevo holds only newsletter subscribers and blocklisted unsubscribers
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
<!-- COMMENTS:END -->
