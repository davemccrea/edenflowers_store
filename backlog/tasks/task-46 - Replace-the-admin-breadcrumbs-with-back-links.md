---
id: TASK-46
title: Replace the admin breadcrumbs with back links
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 20:16'
labels:
  - spec
  - admin
dependencies: []
priority: low
type: refactor
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The admin is two levels deep, a list and then a detail or form, so breadcrumbs add clutter without helping Jennie find her way.

Remove the breadcrumbs from the admin pages that use them and give each detail and form page a back link to its list ("← Orders"). Remove the breadcrumb component if nothing else uses it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No admin page shows breadcrumbs
- [x] #2 Each detail and form page has a back link to its list
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
admin_page_header takes back={{label, path}} in place of the breadcrumb trail and the overview flag. Detail and form pages link back to their list; editing an existing order links back to that order, matching where Save and Cancel return.
<!-- SECTION:NOTES:END -->
