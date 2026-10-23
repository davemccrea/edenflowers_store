---
id: TASK-106
title: Set cancellation terms per course
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each course states how late a booking can be cancelled for a full refund and what is kept after that, and every place that mentions it says the same thing.

**Why:** "After that, we'll work something out" promises nothing clear, and Jennie decides the refund afresh each time. Clear terms let customers know where they stand and prefill her refund.

Decided in the email grilling session on 2026-10-23.

Two fields on a course: the deadline in days before the course, and a fee as a percentage kept after the deadline (100 means no refund). Existing courses start at 7 days and 0%.

The terms sentence is generated from the fields: "Cancel at least 7 days before the course for a full refund. After that, 50% of the price is kept." At 100%: "After that, the booking can't be refunded." At 0% the second sentence is left out. It replaces "we'll work something out" in the course emails, on the course page and in the FAQ.
<!-- SECTION:DESCRIPTION:END -->
