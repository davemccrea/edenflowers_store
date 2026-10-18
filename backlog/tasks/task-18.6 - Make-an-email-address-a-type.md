---
id: TASK-18.6
title: Make an email address a type
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:12'
labels: []
dependencies: []
parent_task_id: TASK-18
type: refactor
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

The same email check, `~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/` with "Must be a valid email address", is written out six times:

- `Order`: `place_custom`, `submit_contact_details`, `edit` (on `:customer_email`)
- `CourseRegistration`: `register`, `add_manually` (on `:email`)
- `AccountLive`: the email-change form, as `String.match?/2`

A change to what counts as a valid address has to find all six, and a new action that accepts an email has to remember the check.

### What to build

- `Edenflowers.Types.Email`, an `Ash.Type.NewType` of `:string` with `constraints: [trim?: true, match: ~r/…/]` and the message. Use it for `Order.customer_email` and `CourseRegistration.email`, and drop the five `validate match(...)` lines: every action accepting the attribute then checks it.
- `User.email` is `:ci_string` (it's the sign-in identity). Leave its type alone, or make a `:ci_string`-based variant if the email-change action should share the check; `AccountLive` then relies on the action's error rather than its own regex.
- No data migration: the column types don't change. Existing rows aren't revalidated.

### Tests

- A unit test for the type: valid, missing `@`, missing dot after `@`, surrounding whitespace trimmed.
- The existing suite passes, with error messages unchanged where tests assert them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The regex exists once
- [ ] #2 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-18 03:24

---

- Replaces the earlier "shared validation module" version of this ticket: a type makes the check impossible to forget (see `TASK-19`).

---
<!-- COMMENTS:END -->
