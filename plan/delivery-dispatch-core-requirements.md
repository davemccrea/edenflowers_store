# Delivery dispatch — core requirements (v1)

> A deliberately small first version of daily delivery routing and driver dispatch.
> This document describes **what** the feature must do in business terms. It avoids
> implementation detail on purpose so the architecture can be designed separately.
> Anything not needed to prove the core loop has been pushed to "Later" (see end).

## Goal

Let the florist turn today's paid delivery orders into an optimized route per driver,
give each driver a stable link to their stops, and watch deliveries get marked done in
real time. The florist can run this more than once a day in waves as orders become
ready and drivers become available.

## The core loop (happy path)

1. In the morning the florist opens the deliveries page. Today's deliverable orders
   are listed and pre-selected.
2. The florist picks which drivers are working today and, if needed, deselects any
   orders that shouldn't go out.
3. The florist optimizes. The system assigns each order to a driver and puts each
   driver's stops in the best order.
4. The florist reviews the proposed routes and publishes them.
5. Each driver opens their own stable link (shared once, e.g. by SMS/WhatsApp) and sees
   today's stops. New waves appear under the same link.
6. Drivers work their list on their phone: tap to navigate, deliver, and record the
   outcome of each stop.
7. The florist watches progress update live until every route is complete.
8. Later in the day the florist can plan another wave for orders that weren't sent yet,
   selecting whoever is now available. Each wave is an independent optimization over the
   orders still eligible.

## User stories

### Florist — planning

- As the florist, I see today's orders that are ready to deliver, pre-selected, so I
  can plan without hunting.
- As the florist, I can deselect orders I don't want to send out today.
- As the florist, I choose which drivers are working today.
- As the florist, I ask the system to build routes, and it assigns orders to drivers and
  orders each driver's stops to keep total driving as low as possible.
- As the florist, I review the proposed routes (which driver gets which stops, in what
  order, with rough distance and time) before committing.
- As the florist, I publish, and from then on each route in that wave is fixed.
- As the florist, later in the day I can plan another wave for orders that haven't gone
  out, with whichever drivers are now available.

### Florist — handing off & monitoring

- As the florist, each driver has one stable link (with a copy button) that I share
  once and that keeps working across waves and days.
- As the florist, I see live delivery progress for every route as drivers record
  outcomes.
- As the florist, I can open any driver's route to see exactly what they see.

### Driver — delivering

- As a driver, I open my link on my phone with no login and see only my stops for
  today, in order.
- As a driver, for each stop I see the recipient's name, a tap-to-call phone number,
  the full address and delivery instructions, the card message, and what's being
  delivered (product names and quantities, no prices).
- As a driver, I tap one button to open Google Maps directions to the stop from where
  I am right now.
- As a driver, I record each stop as delivered (choosing how) or failed (choosing
  why), with an optional note.
- As a driver, completed stops stay visible but collapse out of the way, so I can see
  what's left at a glance.
- As a driver, if a delivery fails I can try it again later in the same day.

### Florist — failed deliveries

- As the florist, I can see on an order's page whether its delivery succeeded or
  failed, when, and why.

### Admin — managing drivers

- As an admin, I can add and edit drivers (name, phone, email, preferred language,
  active/inactive).
- As an admin, I can deactivate a driver so they get no new assignments, without
  losing their history.

## Detailed requirements

### Planning & eligibility

- The deliveries page plans **today only** (shop's local time, Europe/Helsinki).
- An order is eligible when it is placed, paid, pending fulfillment, a delivery (not
  pickup), dated today, and not already on a published route.
- All eligible, unassigned orders start selected; the florist can exclude any.
- Orders are assumed to already have valid delivery coordinates.

#### Waves

- "Wave" is internal terminology only — it is not surfaced in the UI, and there is no
  continuous auto-reoptimization. The florist simply runs the planner again; each run
  is an explicit, independent optimization the florist reviews before publishing.
- The deliveries page can be used more than once a day. Each use plans a **wave**: a
  fresh optimization over the orders still eligible (those not already on a published
  route) with the drivers the florist selects for that wave.
- The page always shows both: the routes already published today (with live progress)
  and the planning controls for whatever is still eligible.
- A driver can appear in more than one wave, getting one route per wave they're in.
  Each wave's route starts fresh from the shop.
- A wave does not touch already-published routes; publishing one is independent of the
  others.

### Drivers & selection

- The florist selects the active drivers who are **available** for the run. This is a
  pool (an upper bound), not a mandate: the optimizer uses however many of them give the
  least total driving and may leave some unused (those simply get no route for the run).
- Defaults that make the common case one click:
  - If only one active driver exists, it's pre-selected.
- All drivers are treated as equivalent in v1 (no capacity differences).

### Optimization & review

- The system assigns orders across the drivers it chooses to use and sequences each
  driver's stops.
- Routes start at the shop and end at the last delivery (no return-to-shop leg). Within
  a route the driver carries the whole load from a single pickup; there is no mid-route
  reload (vehicle capacity is out of scope). When a driver is given orders in a later
  run, that run's route also starts at the shop — which correctly models the driver
  returning to reload, except that the drive back from their previous run is not counted
  and the run assumes selected drivers are available at the shop.
- The optimizer's priority is to **minimise total driving distance** (the cheapest
  plan): assign every order, then minimise kilometres driven. The number of drivers used
  falls out of the geometry — because routes are open (no return leg), HERE uses more of
  the available drivers only when splitting clusters actually saves driving, and
  consolidates otherwise. We add no balancing logic or driver-count dial; the florist's
  driver selection is just the upper bound. (Validated against the live API: e.g. for one
  spread-out set, using two drivers was cheaper than one because it avoided a long
  cross-town leg.) Getting orders to customers *soonest* would instead favour maximum
  parallelism; that's a candidate for a later revision and is not v1's goal.
- The review shows, per driver: the ordered stops, total route distance, driving
  time, and an approximate total duration that includes a short fixed handling time
  per stop. No clock times or arrival estimates are shown.
- The review is a working draft: changing the selected orders or drivers means
  re-optimizing, and the draft is not kept if the page is left.
- If optimization can't place every order, planning is blocked and the florist is
  told. There is no partial publish.

### Publishing & driver links

- Publishing a wave is one explicit action and is all-or-nothing for that wave.
- Each driver selected for the wave gets one route for that wave with their fixed,
  ordered stops.
- Each driver has one stable, unguessable link of their own (the token lives on the
  driver, not the route).
  - The link is shareable and requires no login (drivers don't have accounts).
  - The link is shared once and reused across waves and days. Opening it always shows
    the driver's stops for **today** across every wave they're in; on a day with no
    routes it shows nothing to do.
  - The link must not be guessable, because the page contains customer personal data.
  - An admin can regenerate a driver's link (e.g. if it leaks), which invalidates the
    old one.
- The florist shares each driver's link manually (copy button per driver). The system
  does not send it.

### Driver route page

- Shows the driver's name and today's date.
- Shows the driver's stops for today across every route they're given, each route as
  its own ordered list. Completed stops remain visible but collapsed and clearly marked.
- Each route block is headed by a "Collect from shop" start marker. For a driver's
  first route this just means loading up before leaving; for any later route it is the
  explicit instruction to return to the shop and pick up the new orders before starting
  the new stops.
- Each stop shows: order reference, recipient name, tap-to-call phone, full address,
  delivery instructions, card message, product names and quantities (no prices), and
  the approximate distance/time from the previous stop.
- Each stop has a Google Maps directions link that uses the device's current location
  as the starting point.
- The page renders in the driver's preferred language.

### Recording an outcome

- For each stop the driver records one outcome:
  - **Delivered** — must choose a method: handed to recipient, left in a safe place,
    or other.
  - **Failed** — must choose a reason: recipient unavailable, couldn't access the
    address, couldn't find the address, recipient refused, or other.
  - Choosing "other" requires a note. A note is otherwise optional.
- A delivered outcome immediately marks the order fulfilled.
- A failed outcome leaves the order pending; the stop can be retried the same day.
- Each stop holds a single current outcome. Retrying a failed stop overwrites it with
  the new outcome rather than keeping a per-attempt history. (The kept attempt trail is
  deferred — see Later.)

### Cancellations during the day

- If an order is cancelled or refunded after its route is published, the stop shows as
  "do not deliver" and is skipped. It does not block the route from completing, and
  the rest of the route is not re-ordered.

### Route completion

- A route is complete when every stop is either delivered or cancelled. Any pending or
  failed stop keeps the route open.

### Failed deliveries

- A failed delivery stays on its original route for the rest of that day and is not
  automatically moved to another day.
- A delivery that is still failed at the end of the day is handled outside the system
  in v1 (the florist contacts the customer directly). Rescheduling into a future day's
  plan is deferred.

### Drivers admin

- Drivers have a name, phone, email, preferred language, active/inactive status, and a
  stable link token.
- Drivers are never deleted; deactivation preserves history and stops new assignments.
- A deactivated driver's link still shows any already-published routes for today; it
  just receives no new assignments.
- An admin can regenerate a driver's link token, invalidating the previous link.

## Assumed defaults (please flag if wrong)

- Same-day retry of failed stops is allowed.
- Cancelled/refunded orders are shown as "do not deliver" and skipped, not removed.
- The delivered-method and failed-reason lists above are the v1 set.
- "Other" is the only outcome choice that forces a note.

## Out of scope for v1 (candidate fast-follows)

These were considered and deliberately deferred to keep v1 small. They were designed
out cleanly so they can be added later without rework.

- **Rescheduling a delivery to another day.** v1 does not let the florist move a
  delivery's date. A delivery that fails all day is handled off-system. The data model
  should keep this addable later without rework. (Deferred because changing the date of
  a placed order means carefully relaxing the "placed orders are sealed" policy, which
  is out of proportion to the core loop.)
- **Time-window optimization.** v1 has no per-order delivery time slots and no driver
  working hours; the optimizer minimises driving distance and respects no clock constraints.
  Staggered work is handled by waves (plan again later), not by time windows. Adding
  windows later means delivery-time fields on orders, driver hours, and showing
  clock/arrival times — a separate feature.
- **Kept attempt history.** Each stop stores only its current outcome; retries
  overwrite. A per-attempt trail (and the history view it feeds) is deferred. Adding it
  later means wrapping the current outcome into a list — no rework of the core loop.
- **Proof photos.** Outcomes are recorded without any photo/upload, so v1 needs no
  image storage or serving infrastructure.
- **Automated driver emails.** Links are shared manually instead of emailed.
- **Heavy link security ceremony.** A simple unguessable token is used rather than
  hashing, constant-time matching, etc.
- **Florist recording outcomes on a driver's behalf.** Only the driver's link records
  outcomes in v1.
- **Browsing past days on the deliveries page.** The page is today-only; per-order
  outcomes are still visible on the order page, and the data persists for a future
  history view.

## Explicitly not planned

- Driver authentication or accounts.
- Driver schedules, availability, or vehicle capacities.
- GPS / live driver tracking, offline mode, or printed routes.
- Re-optimizing already-published routes.
- Automatic next-day rollover of failed deliveries.
- Customer-facing delivery notifications or proof of delivery.

## Dependencies / prerequisites

- A route-optimization capability that can assign orders across multiple drivers and
  order each driver's stops. (HERE Tour Planning is the intended provider.) Validate
  its output against realistic local delivery sets before relying on it.
- Public HTTPS app URL for the driver links.
- Orders must carry valid delivery coordinates by the time they reach planning.

## Principal risk (validated)

- The optimizer was the main uncertainty. A spike (`mix eden.tour_planning_spike`)
  against the live HERE Tour Planning API on real Vaasa orders established the request
  shape (vehicles need `capacity`, deliveries need `demand`, objective names are
  camelCase) and settled the objective: v1 minimises **total driving distance** via
  `minimizeUnassigned -> minimizeCost` with cost weighted to distance. With open routes
  the number of drivers used falls out of the geometry, so HERE makes the consolidation
  decision and we add no balancing logic or tuning dial of our own — working with the API
  rather than against it. The end-to-end pipeline and response parsing are verified
  against real output. The rest of the feature is straightforward CRUD and UI around it.
