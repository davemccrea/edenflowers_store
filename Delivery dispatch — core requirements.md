# Delivery dispatch — core requirements (v1)

> A deliberately small first version of daily delivery routing and driver dispatch.
> This document describes **what** the feature must do in business terms. It avoids
> implementation detail on purpose so the architecture can be designed separately.
> Anything not needed to prove the core loop has been pushed to "Later" (see end).

## Goal

Let the florist, once a day, turn today's paid delivery orders into an optimized
route per driver, hand each driver a link to their stops, and watch deliveries get
marked done in real time.

## The core loop (happy path)

1. In the morning the florist opens the deliveries page. Today's deliverable orders
   are listed and pre-selected.
2. The florist picks which drivers are working today (the shop itself can be one of
   them) and, if needed, deselects any orders that shouldn't go out.
3. The florist optimizes. The system assigns each order to a driver and puts each
   driver's stops in the best order.
4. The florist reviews the proposed routes and publishes them.
5. Each driver gets an unguessable link to their personal stop list. The florist
   shares it with them (e.g. by SMS/WhatsApp).
6. Drivers work their list on their phone: tap to navigate, deliver, and record the
   outcome of each stop.
7. The florist watches progress update live until every route is complete.

## User stories

### Florist — planning

- As the florist, I see today's orders that are ready to deliver, pre-selected, so I
  can plan without hunting.
- As the florist, I can deselect orders I don't want to send out today.
- As the florist, I choose which drivers are working today, including the shop itself
  as a "driver."
- As the florist, I ask the system to build routes, and it both assigns orders to
  drivers and orders each driver's stops to keep their finishing times balanced.
- As the florist, I review the proposed routes (which driver gets which stops, in what
  order, with rough distance and time) before committing.
- As the florist, I publish, and from then on each route is fixed for the day.

### Florist — handing off & monitoring

- As the florist, after publishing I see each driver's route link with a copy button,
  so I can send it to them however we already communicate.
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

### Florist — failed & rescheduled deliveries

- As the florist, I can see on an order's page whether its delivery succeeded or
  failed, when, and why.
- As the florist, I can reschedule a delivery to another day, after which it shows up
  in that day's plan automatically.

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

### Drivers & selection

- The florist selects one or more active drivers for the day. The shop itself is one
  of the selectable "drivers" and behaves exactly like any other.
- Defaults that make the common case one click:
  - If only one driver is available, it's pre-selected.
  - If no external drivers are active, the shop is pre-selected.
- Validation: you can't have more drivers than orders, and every selected driver must
  receive at least one stop.
- All drivers are treated as equivalent in v1 (no capacity differences).

### Optimization & review

- The system assigns orders across the selected drivers and sequences each driver's
  stops.
- Routes start at the shop and end at the last delivery (no return-to-shop leg).
- The optimizer's priority is to **balance how late each driver finishes**, then to
  reduce total driving.
- The review shows, per driver: the ordered stops, total route distance, driving
  time, and an approximate total duration that includes a short fixed handling time
  per stop. No clock times or arrival estimates are shown.
- The review is a working draft: changing the selected orders or drivers means
  re-optimizing, and the draft is not kept if the page is left.
- If optimization can't place every order, planning is blocked and the florist is
  told. There is no partial publish.

### Publishing & driver links

- Publishing is one explicit action and is all-or-nothing.
- Each selected driver gets one route for the day with their fixed, ordered stops.
- Each driver route has its own unguessable link.
  - The link is shareable and requires no login (drivers don't have accounts).
  - It works only for its own day; once that day has passed, the page shows an
    expired state and no further outcomes can be recorded.
  - The link must not be guessable, because the page contains customer personal data.
- The florist shares links manually (copy button per driver). The system does not send
  them.

### Driver route page

- Shows the driver's name and today's date.
- Shows the full ordered list of stops. Completed stops remain visible but collapsed
  and clearly marked.
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
- Each attempt is recorded and kept; a later retry adds another attempt rather than
  overwriting.

### Cancellations during the day

- If an order is cancelled or refunded after its route is published, the stop shows as
  "do not deliver" and is skipped. It does not block the route from completing, and
  the rest of the route is not re-ordered.

### Route completion

- A route is complete when every stop is either delivered or cancelled. Any pending or
  failed stop keeps the route open.

### Failed deliveries & rescheduling

- A failed delivery stays on its original route for the rest of that day and is not
  automatically moved to another day.
- The florist can reschedule a delivery from the order's page, which changes only the
  delivery date. Recipient, address, instructions, and past attempts are unchanged.
- Once rescheduled, the order becomes eligible again on its new date.

### Drivers admin

- Drivers have a name, phone, email, preferred language, and active/inactive status.
- Drivers are never deleted; deactivation preserves history and stops new assignments.
- Existing links and routes for a driver keep working if the driver is later
  deactivated.

## Assumed defaults (please flag if wrong)

- Same-day retry of failed stops is allowed.
- Cancelled/refunded orders are shown as "do not deliver" and skipped, not removed.
- The delivered-method and failed-reason lists above are the v1 set.
- "Other" is the only outcome choice that forces a note.

## Out of scope for v1 (candidate fast-follows)

These were considered and deliberately deferred to keep v1 small. They were designed
out cleanly so they can be added later without rework.

- **Same-day re-planning / supplemental trips.** v1 plans once per day. Late orders
  are delivered by the florist or wait for the next day's plan.
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

## Principal risk

- Getting the optimizer to actually express "balance finishing times, then minimize
  driving" is the main uncertainty. Confirm with real Vaasa delivery sets early; the
  rest of the feature is straightforward CRUD and UI around it.
