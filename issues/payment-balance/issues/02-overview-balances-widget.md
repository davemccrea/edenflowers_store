# To collect / To refund on the Overview

Status: ready-for-agent
Type: feature

## What to build

Decision 3 of the spec.

- `Orders` gets a read action listing placed orders where `payable? or balance < 0`, loading `balance`, `customer_name` and `order_reference`.
- `Courses` gets a read action listing registrations that are confirmed or cancelled with `balance != 0`, loading `balance` and the course's name.
- `DashboardLive` gets a widget under the sales widget in the aside, hidden when both lists are empty. Two groups, "To collect" and "To refund", each headed by its count and sum, rows sorted by amount, largest first. An order row links to `/admin/orders/:id`; a booking row to `/admin/courses#course-<course_id>`. Name an order by its customer, falling back to its reference, as the orders widget does.
- Load it in `assign_orders/1`, so the existing `admin:orders` broadcast refreshes it.
- New copy goes through gettext, with en, fi and sv msgstrs.

## Acceptance criteria

- [ ] A fulfilled order still unpaid appears under To collect
- [ ] A cancelled order or booking still holding money appears under To refund
- [ ] A pending booking, an unplaced cart, a settled order and a cancelled order never paid don't appear
- [ ] The widget is absent when nothing is owed either way
- [ ] Each row opens the order, or the courses page at the booking's course

## Blocked by

- 01
