---
id: TASK-64
title: 'Let Jennie proofread every customer email in English, Swedish and Finnish'
status: done
assignee: []
created_date: '2026-10-19 19:41'
updated_date: '2026-10-19 19:44'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 135000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An admin-only Emails page that shows every wording variant of every outgoing email, rendered live by the production email builders, in English, Swedish or Finnish.

**Why:** Wording and translation mistakes in emails are hard to spot without placing orders in each state, and Jennie is the one who can judge the Swedish and Finnish copy. Replaces the gallery scoped in TASK-59 (wontfix) with something much smaller.

## Decisions
- Render live on each page load instead of from generated snapshot files, so the page can never be stale and there is nothing to regenerate. Losing a checked-in text diff of copy changes is accepted.
- Scenarios (fictional data, one per copy-changing branch) live in `Edenflowers.Email.Previews` in lib, built from plain maps passed to the real builders in `Edenflowers.Email`. Building a `%Swoosh.Email{}` never sends, touches the database, Stripe or delivery photos.
- One plain page: a language switch (`?lang=en|sv|fi`) independent of the admin interface language, then a card per email with its title, subject and plain-text body. No filters, no per-scenario metadata, no attachment rendering.
- Scenario titles stay in English; they are for orientation, not customers.
- Lives in the existing `:admin` live session, so it is admin-only like the rest of the admin. Linked from the admin sidebar.
- A test fails when a public builder in `Edenflowers.Email` has no scenario.

## Code pointers
- test/edenflowers/email_snapshot_test.exs holds the scenarios to move
- lib/edenflowers_web/router.ex (`:admin` live session)
- lib/edenflowers_web/components/layouts.ex (admin nav)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An Emails page under /admin, linked from the admin nav, is reachable only by admins
- [x] #2 Switching between English, Swedish and Finnish shows every email rendered in that language, regardless of the admin interface language
- [x] #3 Every email shows a descriptive title, its subject and its plain-text body with line breaks preserved
- [x] #4 A test fails when an email builder has no preview scenario
- [x] #5 The generated preview files and the snapshot comparison test are removed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The internal error alert is left out of the previews: it goes to the developer, not a customer, and its address is only configured where ERROR_ALERT_EMAIL is set.
<!-- SECTION:NOTES:END -->
