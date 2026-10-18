---
id: TASK-47.1
title: Ask whether the customer was home and take a photo if not
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels: []
dependencies: []
parent_task_id: TASK-47
type: feature
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The photo is only worth having if Jennie takes it at the door, in the same step as confirming the delivery.

Confirming a delivery asks "Was the customer home?". No: Jennie takes or uploads a photo (camera capture on her phone) before confirming. Reuse `PhotoUpload` and store it under a random token filename, as uploads are public through imgproxy. The photo shows on the order page and is kept for good.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Confirming a delivery asks whether the customer was home
- [ ] #2 If not, Jennie can take a photo on her phone and it shows on the order page
- [ ] #3 The photo's URL can't be guessed from the order
<!-- AC:END -->
