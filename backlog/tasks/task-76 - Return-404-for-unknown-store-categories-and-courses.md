---
id: TASK-76
title: Return 404 for unknown store categories and courses
status: ready-for-agent
assignee: []
created_date: '2026-10-20 10:26'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: medium
type: bug
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A store category or course URL that doesn't exist answers 404 Not Found, the way unknown products already do.

**Why:** Today `/store/<unknown>` redirects to /store/bouquets and `/courses/<unknown id>` redirects to /courses with a flash. Search engines treat a redirect from a missing page to a general listing as a "soft 404", and a visitor with a broken link isn't told the page is gone (docs/reviews/seo-audit.md, finding 5).

### Decisions

- Raise the same not-found error `ProductLive` raises, so the existing 404 page renders with its navigation.
- Keep the redirects that point somewhere real: `/store` to /store/bouquets, and the empty-bouquets fallback.
- Courses that have passed still exist and keep rendering; only ids with no course 404.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GET /store/<unknown slug> returns 404
- [ ] #2 GET /courses/<unknown or malformed id> returns 404
- [ ] #3 /store still redirects to /store/bouquets, and a past course still renders
<!-- AC:END -->
