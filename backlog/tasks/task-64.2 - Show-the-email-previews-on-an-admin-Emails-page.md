---
id: TASK-64.2
title: Show the email previews on an admin Emails page
status: done
assignee: []
created_date: '2026-10-19 19:42'
updated_date: '2026-10-19 19:44'
labels: []
dependencies:
  - TASK-64.1
parent_task_id: TASK-64
type: feature
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Gives Jennie the page to proofread from.

LiveView at /admin/emails in the `:admin` live session. English / Svenska / Suomi links patch `?lang=`; default English. A card per email: title, subject, body in a whitespace-preserving `pre`. Add an Emails entry to the admin sidebar.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /admin/emails is in the admin live session and linked from the admin sidebar
- [x] #2 `?lang=sv` and `?lang=fi` show the emails in that language whatever the admin interface language
- [x] #3 A non-admin cannot open the page
<!-- AC:END -->
