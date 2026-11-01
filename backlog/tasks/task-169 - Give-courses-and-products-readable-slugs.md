---
id: TASK-169
title: Give courses and products readable slugs
status: needs-triage
assignee: []
created_date: '2026-11-01 21:00'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 314000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Course and product URLs use a readable slug instead of a UUID, e.g. `edenflowers.fi/courses/spring-wreath-workshop` rather than `/courses/de6d2ad5-3277-4dcd-b7bb-e41b3f2d060f`.

**Why:** Links Jennie shares (Instagram, WhatsApp, email, the share drawer) show where they lead before anyone taps them, look trustworthy rather than machine-made, and help search ranking. This replaces the idea of a link shortener: the UUID is what makes links ugly, not the UTM tail.

Today `/:language/product/:id` and `/:language/courses/:id` (and the language-less redirects `/courses/:id`) take the UUID. Both resources have translated names.

Open questions (grill before implementing):
- One slug per record, or one per language from the translated name (`/sv/kurser/...`)?
- Generated from the name, editable in the admin, or both?
- When a name or slug changes, do old slugs keep redirecting (slug history) or is that rare enough to skip?
- Must existing UUID links keep working (redirect to the slug URL)? Likely yes: links are already shared and printed.
- Uniqueness and clashes, e.g. two courses with the same name on different dates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Course and product pages are reachable at a readable slug URL
- [ ] #2 Links already shared with a UUID still land on the right page
- [ ] #3 The admin share drawer copies the slug URL
<!-- AC:END -->
