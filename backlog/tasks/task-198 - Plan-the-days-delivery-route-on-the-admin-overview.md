---
id: TASK-198
title: Plan the day's delivery route on the admin overview
status: ready-for-human
assignee: []
created_date: '2026-11-13 21:37'
updated_date: '2026-11-13 23:07'
labels:
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 363000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie plans the fastest order to drive a day's deliveries in, from the overview, and hands it to Google Maps.

**Why:** Today she opens each order's Directions link one at a time and works out the order in her head. A planned route saves driving time and makes sure the "by 10:30" Custom Orders get there in time.

## Decisions (grilled 2026-11-13)

- A "Plan route" button by the selected day's Delivery heading on the overview opens a drawer.
- Stops: every placed delivery that day that hasn't been handed over (pending or Ready) starts ticked; she can untick any. Orders without a geocoded `position` are listed under "Not on the route".
- Start and End are chosen separately: Shop or Home, defaulting to Shop → Shop. Home comes from `HOME_POSITION="lat,lng"` in the environment, never committed (the repo is public). Without it, only Shop is offered.
- Departure time field: now for today, 09:00 for other days.
- Planning is on a button press, never automatic: each plan is a HERE request.
- HERE Waypoints Sequence (`findsequence2`), car, fastest, traffic from departure. 5 minutes service per stop. A Custom Order's `fulfillment_time_start`/`end` is a hard access window. If no order can meet every window, or HERE fails, the drawer says so.
- Result: the ordered stops with estimated arrival and any agreed window, total distance and drive time, and "Open in Google Maps" with the stops in order (about 9 waypoints per link; more get split into parts).
- Planning is a generic action in the Fulfillment domain; nothing is stored.

Not doing: a map in the drawer, saved routes, stem counts or the wholesaler list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The overview's Delivery group for a day opens a route drawer listing that day's deliveries not yet handed over, Ready ones ticked, and those without a position under Not on the route
- [x] #2 Planning returns the ticked stops in HERE's order with arrival estimates, total distance and drive time, starting and ending at the chosen Shop or Home
- [x] #3 A Custom Order's agreed time window is sent as a hard window, and an infeasible window or HERE failure is shown rather than a wrong route
- [x] #4 Start delivery run numbers today's planned stops; the Overview's day list and the order page's next arrow follow that order, and Directions opens one stop at a time by HERE's address
- [x] #5 Home is offered only when HOME_POSITION is set, and the home position is not in the repository
- [ ] #6 HOME_POSITION is set in production
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Changed after review (2026-11-14): the multi-stop Google Maps links are gone (mobile Google Maps takes only 3 waypoints). Instead 'Start delivery run' stores each stop's route_position on its order; to_fulfil and due_soon sort by it within a day, so the order page's next arrow walks the run and Directions opens one stop at a time, by HERE's geocoded address with coordinates as fallback. Ready orders start ticked; others can be ticked by hand. A saved DeliveryRun resource was considered and dropped as a copy of the order page.

UI/UX pass (2026-11-14): after planning today's route the drawer's footer offers Start delivery run, with Plan again beside it; a changed form keeps the old route dimmed as out of date and not startable; deliveries that miss their window are marked in the stop list; other days say the run starts on the day; HERE failures and bad input get different messages. With a run on, the drawer ticks its stops left and warns a new run replaces it. The run card counts delivered stops (new `delivery_run` read) and sets the next stop larger with Directions beside it. On a run stop, the order page's nav reads Stop N of M, and after delivering, the run's stops left instead of every order still to fulfil.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-13 21:51

---

Built and verified against live HERE in the delivery-route worktree. Left for David: run the Ansible playbook so production's compose file gets HOME_POSITION (it's in the vault), then deploy; tick AC #6 once Home shows in the production drawer.

---
<!-- COMMENTS:END -->
