---
id: TASK-169
title: Give courses and products readable slugs
status: ready-for-agent
assignee: []
created_date: '2026-11-01 21:00'
updated_date: '2026-11-01 21:15'
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

Today `/:language/product/:id` and `/:language/courses/:id` (and the language-less redirect `/courses/:id`) take the UUID.

Decisions (grilled 2026-11-01):
- **Shape:** slug only, no ID suffix. One slug per record for all languages.
- **Source:** generated from the English base `name` (like category slugs). One shared slugify function transliterates (å/ä/ö to a/a/o), lowercases, turns spaces into hyphens and drops other characters. Jennie's typed slugs are normalised the same way, not rejected.
- **Rename:** the slug stays put when the name changes. It only changes when Jennie edits it.
- **Old links:** UUID URLs permanently redirect to the slug URL. Earlier slugs are remembered and permanently redirect to the current one, and stay reserved: no other record can take them.
- **Storage of earlier slugs:** a small table per resource with a unique slug, so the database enforces the reservation. Product and course slugs are separate namespaces.
- **Clashes:** the generator adds -2, -3, … Jennie can edit it to something nicer. `bookings` and `pay` are reserved for courses.
- **Admin:** a Link field showing `edenflowers.fi/courses/[slug]`. On a new record it fills from the name as she types until she edits it; on an existing record it is a normal field.
- **Links:** everything that builds a course or product URL (share drawer, emails, sitemap, admin view links) uses the slug.
- **Rollout, two deploys:** deploy 1 adds a nullable slug and `Release.migrate` backfills missing slugs after migrating; deploy 2 makes the slug required. Migrations stay generated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Course and product pages are reachable at a readable slug URL
- [ ] #2 Links already shared with a UUID still land on the right page
- [ ] #3 The admin share drawer copies the slug URL
<!-- AC:END -->
