---
id: TASK-31
title: Call the course a course in booking emails
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:38'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: feature
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** "Din plats på Julkrans är bekräftad" reads oddly: customers expect "på kursen Julkrans". Jennie raised it when reading the emails through.

Change the copy in en/fi/sv:

- "Your place on %{course} is confirmed" becomes "Your place on the course %{course} is confirmed" (sv: "Din plats på kursen %{course} är bekräftad"), and the same in the subject and headings that name the course.
- The payment-link email: "Här är en länk där du kan betala din bokning till %{course} online, med kort eller MobilePay, före kursen:" becomes "Här är en länk där du kan betala din bokning till kursen %{course} online, med kort eller MobilePay:". Same change in en and fi.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The course confirmation email and its subject say 'the course <name>' in en, fi and sv
- [x] #2 The payment-link email says 'your booking for the course <name>' and no longer ends with 'before the course'
<!-- AC:END -->
