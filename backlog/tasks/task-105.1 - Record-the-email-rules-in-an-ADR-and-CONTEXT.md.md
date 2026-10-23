---
id: TASK-105.1
title: Record the email rules in an ADR and CONTEXT.md
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 18:52'
labels: []
dependencies: []
parent_task_id: TASK-105
type: feature
ordinal: 214000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The rules change how every email is designed, and the next person adding one needs to find them without this session.

Write an ADR for rules 1 to 3 of the parent (one email per job, who acted decides the voice with Jennie as the default, tick box and message box on every email Jennie triggers). It sits beside ADR 0005, which still holds for how emails are queued. Add the email names that are domain words (Payment reminder, Payment received) to CONTEXT.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An ADR records the three rules and the options considered (versioned emails, strict per-actor voice)
- [ ] #2 CONTEXT.md defines Payment received and Payment reminder
- [ ] #3 CONTEXT.md defines Charge day (3 days before delivery, the Occurrence is created and charged) and Change deadline (5 days before, the last day a customer can pause, change or cancel; Online Orders share it for a customer's own cancellation)
<!-- AC:END -->
