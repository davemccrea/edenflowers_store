---
id: TASK-64.1
title: Build every email's preview scenarios in lib
status: done
assignee: []
created_date: '2026-10-19 19:42'
updated_date: '2026-10-19 19:44'
labels: []
dependencies: []
parent_task_id: TASK-64
type: refactor
ordinal: 136000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The Emails page needs the scenarios at runtime, so they move out of the snapshot test into `Edenflowers.Email.Previews`.

Expose `Edenflowers.Email.Previews.all(locale)` returning `{title, builder, %Swoosh.Email{}}` for every scenario, rendered in that locale. Replace the snapshot test with a coverage test and delete priv/email_previews/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `Edenflowers.Email.Previews.all/1` renders every scenario in the given locale through `Edenflowers.Email`
- [x] #2 A test fails when a public builder in `Edenflowers.Email` has no scenario
- [x] #3 priv/email_previews/ and the snapshot test are gone
<!-- AC:END -->
