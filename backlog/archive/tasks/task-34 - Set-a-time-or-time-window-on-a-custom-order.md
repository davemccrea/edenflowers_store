---
id: TASK-34
title: Set a time or time window on a custom order
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 19:02'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can give a custom order an exact time (14:00) or a window (14:00–15:00), and everyone who reads the order sees it.

**Why:** Customers ask for a time and Jennie keeps it in her head or the florist note today. TASK-1 (paid delivery windows at checkout) needs the same data later, so this lays it down for the admin first.

Add optional `fulfillment_time_start` and `fulfillment_time_end` to Order. In the custom order form, a three-way toggle next to the date: **Any time** | **At** (one time field) | **Between** (two time fields), so no field's meaning depends on being blank. Between needs end after start. Show the time on the order page, the fulfillments list and in the customer's emails ("kl. 14:00", "kl. 14–15"). Checkout doesn't set it yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The custom order form offers Any time, At and Between, and saves the matching times
- [x] #2 Between refuses an end at or before the start
- [x] #3 The time shows on the order page, the fulfillments list and the order emails
- [x] #4 Online orders are unchanged
<!-- AC:END -->
