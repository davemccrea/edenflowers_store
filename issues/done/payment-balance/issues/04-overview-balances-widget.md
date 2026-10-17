# To collect / To refund on the Overview

Status: done
Type: feature

## What to build

Decision 6 of the spec.

- A read action in each domain listing records that are `committed?` and not `settled?`: orders loading `balance`, `customer_name` and `order_reference`; bookings loading `balance`, `name` and the course's name and id.
- A widget on `DashboardLive`, under the sales widget in the aside, hidden when both lists are empty. Two groups, "To collect" and "To refund", each headed by its count and sum, rows largest first. An order row links to `/admin/orders/:id` and is named by its customer, falling back to its reference; a booking row links to `/admin/courses#course-<course_id>` and names the course.
- Loaded in `assign_orders/1`, so the `admin:orders` broadcast refreshes it.
- New copy through gettext, with en, fi and sv msgstrs.

## Tests

- Each read action, against the shared builders: lists unpaid, part-paid and cancelled-still-holding-money records; leaves out settled, refunded-in-full, cancelled-never-paid and uncommitted ones.
- LiveView: a fulfilled order still unpaid and a cancelled booking paid in cash appear under the right groups with the right sums; the widget is absent when nothing is owed; rows link to the order and to the course.
- The widget updates when an order is paid while the Overview is open.

## Acceptance criteria

- [ ] Every case above passes
- [ ] The widget reads only the domain read actions; no balance logic in the LiveView
- [ ] The existing suite passes

## Blocked by

- 01
