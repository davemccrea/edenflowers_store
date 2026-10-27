---
id: TASK-85
title: Rename a course's image_slug to photo_slug
status: done
assignee: []
created_date: '2026-10-21 15:39'
updated_date: '2026-10-27 13:57'
labels:
  - spec
  - developers
  - wontfix
dependencies:
  - TASK-84.1
priority: low
type: refactor
ordinal: 173000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Courses call their photo `photo_slug`, matching products and sizes after TASK-84.

**Why:** after TASK-84 products and sizes say "photo" (`photo_slugs`, `main_photo_slug`, `photo_slug`) while courses still say `image_slug`, so whoever reads the code next has two names for the same thing.

- Rename the Course attribute `image_slug` to `photo_slug` and update its actions' accept lists, the course form (`@photo_fields`, the `photo_input` field), the store course page, the generator, seeds and tests.
- Generate the migration with `mix ash.codegen` (a column rename; check it renames rather than drops and adds).
- Line items keep `product_image_slug`; renaming that snapshot column is out of scope.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Course has photo_slug and no image_slug, and course photos show everywhere they did before
- [ ] #2 The generated migration renames the column without losing data
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: closed. Cosmetic rename; a column-rename migration before launch is risk for no gain.

---
<!-- COMMENTS:END -->
