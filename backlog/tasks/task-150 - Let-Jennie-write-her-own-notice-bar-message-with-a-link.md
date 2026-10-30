---
id: TASK-150
title: Let Jennie write her own notice bar message with a link
status: needs-triage
assignee: []
created_date: '2026-10-30 19:25'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can write her own message for the bar above the storefront header, with a link, in place of the automatic order-deadline line.

**Why:** The bar is the most visible line on every storefront page, but today it only shows the order deadline or next open day (`EdenflowersWeb.Hooks.PutNoticeBar`, from `Availability.order_status/2`). Jennie wants to use it for her own news, such as a Mother's Day reminder or a new course, and link to the right page. Raised in review note #38.

**Open (grill before building):**
- Does her message replace the deadline line, or alternate with it? What happens on days the shop is closed?
- Does she write it in sv, fi and en, and what does a missing language fall back to?
- Is the link any URL or only a storefront page? Is the whole bar the link, as it is now (it links to the shop)?
- Does it have a start and end date, or does it stay until she clears it?
- Where does she edit it in admin, and is a length limit enforced (about 45 characters fits one line on a 320px phone)?
<!-- SECTION:DESCRIPTION:END -->
