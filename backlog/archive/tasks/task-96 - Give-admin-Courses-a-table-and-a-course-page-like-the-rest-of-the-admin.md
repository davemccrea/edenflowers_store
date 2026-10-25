---
id: TASK-96
title: 'Give admin Courses a table and a course page, like the rest of the admin'
status: done
assignee: []
created_date: '2026-10-22 19:35'
updated_date: '2026-10-22 20:33'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 203000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Admin Courses becomes a Cinder table of courses that opens a page per course, the way Orders and Products work.

**Why:** Courses is the one admin section built differently: a stack of collapsible cards with every booking, payment, refund and cancellation inline on the list, so it feels unlike the rest of the admin. Fully settled past courses also drop off the list (`Course.admin_list`), so Jennie can't look at them at all.

## Today

- `/admin/courses` (`CoursesLive`, ~900 lines) lists upcoming courses plus past ones with unsettled bookings, each as a `<details>` card holding its bookings, their action menus, and the booking, settlement and cancel drawers.
- `/admin/courses/:id` is the edit form (`CourseFormLive`).
- The Overview links to `/admin/courses?booking=<id>` to open a course and point at a booking.

## Decisions

### List, `/admin/courses`

- Cinder table with name, date, time, seats booked / total and a "To settle" badge when any booking is committed and not settled. Time and seats hidden on phones.
- A "When" select filter (Current / Past / All) on a `period` calculation. It opens on Current, soonest first, through `DefaultTableView` as Orders does. Current is upcoming plus past ones still to settle.
- Seats count confirmed bookings only (`seats_booked`), not holds still at checkout, so the count matches the bookings the page lists.
- Clicking a row opens the course page. The table refreshes on `admin:bookings`.
- `list_admin_courses` goes.

### Course page, `/admin/courses/:id`

- Header: name, date and time, seats taken / total. Actions: Add booking, Email everyone, Edit.
- Body: the card body moved across as it is (booking rows, action menus, cancelled fold, the three drawers).
- With one course on the page, the `{course, booking}` tuples, `find_booking` and `booking_course_id` go.
- Move the drawers to their own module only if the file is still over ~600 lines after these cuts.
- Unknown id: flash "Course not found." and go to the list. Reloads its course on `admin:bookings`.
- The Overview's `?booking=` links point here and still highlight the booking. Nothing else links to the old URL, so it needn't keep working.

### Form, `/admin/courses/:id/edit` and `/admin/courses/new`

- Creating goes to the new course's page. Editing stays on the form after saving.
- Back from edit goes to the course page, from new to the list.

### Not in scope

A page per booking (bookings have no history log), a summary card on the course page, a language column.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /admin/courses shows current courses in a Cinder table, and a Current / Past toggle lists every past course, settled or not
- [x] #2 Each course has a page at /admin/courses/:id where its bookings are managed as they are today
- [x] #3 The course form lives at /admin/courses/:id/edit; creating a course lands on its page
- [x] #4 Overview booking links open the booking's course page with the booking highlighted
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Changed while building: Q6 went to a Cinder filter after finding DefaultTableView, which opens a table on a default filter. The page header and table count confirmed seats (new seats_booked aggregate), because seats_taken includes checkout holds the page hides. The drawers moved to CourseBookingDrawers as the page was still 822 lines (now 640).
<!-- SECTION:NOTES:END -->
