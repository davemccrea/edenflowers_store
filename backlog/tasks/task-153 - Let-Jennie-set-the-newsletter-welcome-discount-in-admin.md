---
id: TASK-153
title: Let Jennie set the newsletter welcome discount in admin
status: ready-for-agent
assignee: []
created_date: '2026-10-31 08:53'
updated_date: '2026-10-31 20:45'
labels:
  - customers
  - admin
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 289000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie sets the newsletter welcome discount in admin, including limited-time offers like 25% around the reopening email, and every place that mentions it shows the right percent.

**Why:** The 15% welcome rate is hard-coded in the code generator and seven customer-facing strings, so changing it needs a developer and a deploy. Jennie wants 25% for a limited time now and to run offers like it herself later.

Decisions (2026-10-31, revised from dated offers to one editable percent):

Model
- One editable welcome percent, kept in a small single-row Pricing resource (not an env var: changing that needs a deploy). Kept separate from Promotion, because a Promotion row needs a code and a template row would be redeemable at checkout.
- No dates. A limited-time offer is Jennie changing the percent and changing it back herself (calendar reminder). If she forgets, new subscribers keep the higher rate, which is generous but never misleading, since the site shows no end date.
- Until Jennie sets it, the percent is 15%. No production data fix and no hand-written seed migration.
- A new subscriber's one-use code takes the percent set at signup. The code stays valid for 30 days from signup, as now. Codes already sent keep their rate.

Admin
- A Welcome offer field on the Promotions page where Jennie sees and changes the percent.

Copy
- The footer signup and the checkout opt-in show the current percent.
- The welcome and already-subscribed emails show the rate on the subscriber's own code, so an old 15% code is never described as 25%.
- New msgids with the percent as a placeholder; sv/fi translated for Jennie to review.
- Only the reopening email (TASK-152) names the deadline, filled in once the send date is set.

Not now
- Dated offers, overlap checks and linking each code to the offer it came from. Add them if Jennie forgets to switch back or asks whether an offer worked.

After deploy
- Jennie sets 25% when the reopening email is sent and back to 15% two weeks later; then the reopening email is updated to 25% with that end date.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can see and change the welcome percent from the Promotions page in admin
- [ ] #2 A subscriber gets a one-use code at the percent set when they sign up, valid for 30 days
- [ ] #3 Until Jennie sets a percent, signups get a 15% code
- [ ] #4 The footer signup and the checkout opt-in show the current percent in sv, fi and en
- [ ] #5 The welcome and already-subscribed emails show the percent on the subscriber's code
- [ ] #6 Codes sent before a change keep their rate
<!-- AC:END -->
