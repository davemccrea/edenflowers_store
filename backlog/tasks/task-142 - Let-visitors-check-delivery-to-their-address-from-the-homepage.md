---
id: TASK-142
title: Let visitors check delivery to their address from the homepage
status: needs-triage
assignee: []
created_date: '2026-10-29 03:14'
labels:
  - customers
  - spec
dependencies: []
priority: medium
type: feature
ordinal: 277000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An address input in the homepage's Delivery and pickup section tells a visitor whether Jennie delivers there and what it costs, before they choose a bouquet.

**Why:** Delivery is priced by distance, so visitors only learn their fee at checkout. Answering it up front removes a reason to hesitate (review note #12 asked about checking delivery distance or cost).

FulfillmentOption.calculate_delivery already geocodes an address with HERE and prices it; checkout uses it.

Open questions (grill before building):
- Abuse and cost: every lookup calls HERE from a public page; rate limit with ash_rate_limiter? Per IP or session, how many lookups?
- What it answers: just the fee, or also free delivery within the free radius, which depends on the bouquet? Wording for addresses outside the delivery range?
- Should a checked address carry over into checkout?
- Placement: only this section, or also the delivery FAQ?
<!-- SECTION:DESCRIPTION:END -->
