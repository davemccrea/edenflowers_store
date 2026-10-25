---
id: TASK-84.2
title: Manage a product's photos and each size's photo in the product form
status: done
assignee: []
created_date: '2026-10-21 15:35'
updated_date: '2026-10-21 15:50'
labels: []
dependencies:
  - TASK-84.1
parent_task_id: TASK-84
type: feature
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie adds, removes and orders a product's photos in one place and picks each size's photo from them, without the per-size uploads that crashed the form.

- One gallery area in the form's Photo section: drop or pick up to 8 photos. Each is stored when its upload finishes (`auto_upload` plus a progress callback that consumes the entry), so it has its final slug straight away.
- Each photo has "Remove" and "Make main". The main photo is marked.
- Each size row shows a row of thumbnail radios, "Main photo" first, then the product's photos. Picking one sets the size's `own_photo_slug`; "Main photo" clears it.
- Delete the per-size upload machinery from ProductFormLive: dynamic upload names, `PhotoUpload.forget` on size removal, `assign_form` allowing uploads per size. Also drop the `fallback` attr from `PhotoUpload.photo_input` (only size rows used it) and the regression test for sizes added by validation; replace it with one that adding and removing sizes never needs an upload. Keep `photo_input` for courses and delivery photos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can add up to 8 photos, remove one, and make any photo the main one
- [x] #2 A size's photo is chosen from the product's photos or left as the main photo
- [x] #3 Adding and removing sizes in any order never crashes the form
- [x] #4 Course and delivery photo uploads work as before
<!-- AC:END -->
