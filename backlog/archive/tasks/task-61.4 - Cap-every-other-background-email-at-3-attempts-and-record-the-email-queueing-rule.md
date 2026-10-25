---
id: TASK-61.4
title: >-
  Cap every other background email at 3 attempts and record the email queueing
  rule
status: done
assignee: []
created_date: '2026-10-19 20:08'
updated_date: '2026-10-19 20:16'
labels: []
dependencies: []
parent_task_id: TASK-61
type: chore
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** payment-failed, subscription setup, order cancelled, sign-in code, email-change code, wedding enquiry, newsletter promo and error alert emails retried up to 20 times over several days, so a broken one kept trying long after it mattered. Writing the rule down keeps the next email consistent.

Set `max_attempts 3` on each, keeping the payment-failed `where` because it checks the email still makes sense when the job runs. Record the rule in ADR 0005: every background email is one queued job with 3 attempts; failures reach ErrorTracker and are retried from `/oban`; a `_failed_at` field and resend control only where Jennie acts on a failure herself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every background email job has max_attempts 3
- [x] #2 ADR 0005 records when an email gets a failure field
<!-- AC:END -->
