---
id: TASK-168.1
title: Record business customer details on orders and Course bookings
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
labels: []
dependencies: []
parent_task_id: TASK-168
type: feature
ordinal: 315000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** An invoice to a company needs its name, Y-tunnus and billing address, and Jennie should be able to enter them whenever she learns them, without that blocking the order.

Add a "Business customer" checkbox to orders and Course bookings, with company name, Y-tunnus, billing address and an optional customer reference (viitteenne / PO). Show the fields in the custom order form and the admin booking form when the box is ticked. Saving never requires them. Add a calculation saying whether the business details are complete, for the invoice action to validate against. Validate the Y-tunnus format and check digit when one is given.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Orders and Course bookings store the business flag and details
- [ ] #2 The custom order and admin booking forms show the fields when Business customer is ticked
- [ ] #3 Saving with incomplete business details succeeds
- [ ] #4 A calculation reports whether business details are complete
- [ ] #5 An invalid Y-tunnus is rejected with a clear error
<!-- AC:END -->
