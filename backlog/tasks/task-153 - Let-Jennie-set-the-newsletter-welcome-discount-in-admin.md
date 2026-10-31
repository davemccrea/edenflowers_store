---
id: TASK-153
title: Let Jennie set the newsletter welcome discount in admin
status: ready-for-agent
assignee: []
created_date: '2026-10-31 08:53'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 289000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie sets the newsletter welcome discount in admin, including limited-time offers like 25% around the reopening email, and every place that mentions it shows the right percent.

**Why:** The 15% welcome rate is hard-coded in the code generator and seven customer-facing strings, so changing it needs a developer and a deploy. Jennie wants 25% for a limited time now and to run offers like it herself later.

Decisions (2026-10-31):

Model
- New Pricing resource for welcome offers: percent, optional start date and end date. Kept separate from Promotion, because a Promotion row needs a code and a template row would be redeemable at checkout.
- An offer without dates is the standing offer (15% today). A dated offer overrides it while it runs.
- Dated offers can't overlap: saving one that overlaps another fails with a clear error.
- A new subscriber's one-use code takes the rate of the offer running that day (Helsinki date). The code stays valid for 30 days from signup, as now. Codes already sent keep their rate.
- If no standing offer exists, signups get a built-in 15% and admin prompts Jennie to set one. She creates the standing offer after deploy; no production data fix.

Admin
- A Welcome offers section on the Promotions page, where Jennie adds and edits offers.

Copy
- The footer signup and the checkout opt-in show the current offer's percent; no end date on the site.
- The welcome and already-subscribed emails show the rate on the subscriber's own code.
- New msgids with the percent as a placeholder; sv/fi translated for Jennie to review.
- Only the reopening email (TASK-152) names the deadline, filled in once the send date is set.

After deploy
- Jennie creates the 15% standing offer and a 25% offer ending two weeks after the reopening email is sent; then the reopening email is updated to 25% with that end date.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can add, edit and remove welcome offers from the Promotions page in admin
- [ ] #2 A subscriber gets a one-use code at the rate of the offer running on the day they sign up, valid for 30 days
- [ ] #3 A dated offer overrides the standing offer only between its start and end dates
- [ ] #4 Saving a dated offer that overlaps another dated offer fails with a clear error
- [ ] #5 With no standing offer, signups still get a 15% code and admin prompts Jennie to set one
- [ ] #6 The footer signup and the checkout opt-in show the current offer's percent in sv, fi and en
- [ ] #7 The welcome and already-subscribed emails show the percent on the subscriber's code
- [ ] #8 Codes sent before the change keep their rate
<!-- AC:END -->
