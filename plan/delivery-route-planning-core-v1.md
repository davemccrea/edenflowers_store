# Plan: Core delivery route planning v1

## Purpose

Ship the smallest useful delivery workflow:

1. The florist opens `/admin/deliveries`.
2. Today's paid, pending delivery orders are selected.
3. The florist selects drivers.
4. HERE assigns and orders the deliveries.
5. The florist reviews a list preview and publishes it.
6. Each driver receives one secret link by email.
7. The driver opens an ordered delivery list, navigates with Google Maps, and marks
   deliveries as completed.

This is intentionally narrower than
[`delivery-route-planning.md`](delivery-route-planning.md). It implements only the
behavior required for the first useful release. The later feature may require
migrations and refactoring.

## Core scope

### Admin workflow

- Add `/admin/deliveries` to the normal admin navigation.
- The page handles only today in `Europe/Helsinki`; there is no date picker.
- Show eligible orders:
  - `state == :placed`
  - `payment_status == :paid`
  - `fulfillment_status == :pending`
  - `fulfillment_method == :delivery`
  - `fulfillment_date == today`
  - not already assigned to a published route
- Preselect every eligible order and allow the florist to uncheck orders.
- List `Driver` records.
- If there are no drivers, disable optimization and direct the florist to add one in
  AshAdmin.
- If there is exactly one driver, preselect it.
- Require at least one order and one driver.
- Do not allow more drivers than orders.
- Call HERE Tour Planning synchronously.
- Show a list-only preview grouped by driver:
  - Ordered delivery stops.
  - Total distance.
  - Estimated driving time.
  - Five minutes of service time per delivery.
- Keep preview state only in LiveView memory.
- Publish only after the florist clicks an explicit button.
- After any route has been published today, make the page a read-only progress view.
  New same-day orders and supplemental trips are deferred to the full plan.

### Driver workflow

- Each driver receives an email containing a high-entropy secret link.
- The link is valid only for that delivery date and expires at midnight in
  `Europe/Helsinki`.
- Generate the link with a Phoenix-signed token containing the route ID. Store no
  route token in the database.
- Show the driver's name, date, and full ordered list.
- Each stop shows:
  - Order reference.
  - Recipient name.
  - Tap-to-call recipient phone number.
  - Delivery address.
  - Delivery instructions.
  - Card message.
  - Product names, variants, and quantities without prices.
  - Approximate distance and driving time from the previous stop.
  - Google Maps link to the delivery, using the device's current location.
- Each pending stop has `Mark delivered`.
- Use a small daisyUI-styled native `<dialog>` to confirm completion.
- Confirmation calls the existing order fulfillment action.
- Keep completed stops in the list, collapsed and visibly marked.
- Show `Route complete` when all stops are completed.
- Recheck token date validity for every mutation, not only on mount.

### Driver administration

- Add an AshAdmin-managed `Driver` resource.
- Fields:
  - Name.
  - Unique email.
- Use the application's default locale for the email and route page.

## Minimal domain model

### `Driver`

- `id`
- `name`
- `email`
- timestamps

### `DeliveryRoute`

One daily route per driver.

- `id`
- `delivery_date`
- `driver_id`
- total distance
- total driving duration
- total service duration
- `published_at`
- timestamps

Constraints:

- Unique driver and date.

### `DeliveryStop`

- `id`
- `delivery_route_id`
- `order_id`
- `sequence`
- leg distance
- leg driving duration
- timestamps

Constraints:

- An order may be assigned to only one delivery stop.
- Sequence is unique within a route.
- Delivery completion is derived from the related order's `fulfillment_status`.

## Implementation plan

### 1. Add resources and migrations

- Add `Driver`, `DeliveryRoute`, and `DeliveryStop` Ash resources.
- Register them in `Edenflowers.Store`.
- Add relationships, identities, AshAdmin configuration, code interfaces, and
  policies.
- Generate migrations and resource snapshots.
- Add a read action for today's eligible delivery orders.

Tests:

- Driver email uniqueness.
- One daily route per driver.
- One stop per order.
- Stop sequence uniqueness.

### 2. Add the HERE Tour Planning adapter

- Leave `Edenflowers.HereAPI` geocoding and distance behavior unchanged.
- Add a separate `Edenflowers.HereTourPlanning` behavior and implementation.
- Send:
  - Selected orders as delivery jobs.
  - Selected drivers as equivalent car vehicles.
  - Shop coordinates as each vehicle's start.
  - No required return destination.
  - Five-minute service duration per job.
  - A broad `08:00-23:59 Europe/Helsinki` nominal shift.
- Parse HERE output into an internal preview struct containing driver assignment,
  ordered order IDs, leg metrics, and totals.
- Reject responses containing missing, duplicate, unknown, or unassigned orders.
- Configure the adapter through application environment so tests can use Mox.

Tests:

- One-driver ordering.
- Multi-driver assignment.
- Parsed leg and route totals.
- Invalid and incomplete HERE responses.
- Transport/API failure.

### 3. Publish routes atomically

- Add a dispatch service that accepts the reviewed preview.
- Do not call HERE inside the database transaction.
- In one transaction:
  - Create one `DeliveryRoute` per selected driver.
  - Create ordered `DeliveryStop` records with HERE metrics.
- Reject publication if any selected order is already assigned.

Tests:

- All routes and stops commit together.
- Failure leaves no partial routes.
- Every selected order is persisted exactly once.

### 4. Send driver emails

- Add a route email using the application's default locale:
  - Driver name.
  - Delivery date.
  - Number of stops.
  - Approximate distance and duration.
  - Secret route URL.
- Add an Oban worker receiving only the route ID. It generates the signed route URL
  when the job runs.
- Queue one job per route after successful publication.
- Do not add delivery-status tracking or resend controls in v1.

Tests:

- Correct recipient.
- Correct date-bound route URL.
- Idempotent job behavior.

### 5. Build the admin Deliveries page

- Add `/admin/deliveries` inside the authenticated admin LiveSession.
- Add a normal admin navigation link.
- Before publication:
  - Load and preselect eligible orders.
  - Load drivers.
  - Validate selections.
  - Run optimization.
  - Render grouped preview.
  - Publish.
- After publication:
  - Show each route's ordered list and completion count.
- A page refresh before publication discards the preview.
- A page refresh after publication loads persisted routes.

Tests:

- Eligibility and default selections.
- Selection validation.
- HERE loading and failure states.
- Preview rendering.
- Successful publication.
- Published progress rendering.

### 6. Build the route page

- Add a public LiveView route containing the raw secret token.
- Verify the Phoenix signature, load the referenced route, and require its
  `delivery_date` to equal today.
- Build Google Maps links with only `destination` and `travelmode=driving`, allowing
  Google Maps to use current location.
- Render a daisyUI modal using native `<dialog>` for delivery confirmation.
- On confirmation:
  - Mark the order fulfilled.
  - Reload progress.
- Reject expired links and post-midnight completion attempts.

Tests:

- Valid, invalid, and expired tokens.
- Driver detail visibility and hidden prices/payment data.
- Google Maps destination links.
- Confirmation dialog behavior.
- Order fulfillment.
- Completed-stop rendering.
- Route-complete state.

### 7. Localize and verify

- Use Gettext sigils for all public route text, email text, admin messages, and
  confirmation copy.
- Do not log signed route URLs or recipient details.
- Set a restrictive referrer policy on the secret route page.
- Run:

```sh
source .env
mix format
mix compile --warnings-as-errors
mix test
mix precommit
```

## Explicitly deferred to the full plan

- Supplemental same-day trips and return-to-shop rows.
- Adding orders after initial publication.
- Assigning routes directly to a florist/admin without a `Driver` record.
- Driver preferred language and active/inactive status.
- Re-optimization or route modification.
- Failed-delivery outcomes and retries.
- Delivery methods, failure reasons, notes, and attempt history.
- Proof-photo uploads, local storage, and imgproxy integration.
- PubSub live updates between driver and admin pages.
- Admin-entered driver outcomes.
- Historical date picker and route history UI.
- Rescheduling failed deliveries.
- Refunded-order route handling.
- Address locking after dispatch.
- Driver remaining-stop counts during supplemental planning.
- Customer notifications.
- GPS, offline mode, maps, printing, capacities, time windows, and WhatsApp.

## Core acceptance criteria

- A florist can optimize and publish today's selected eligible orders across one or
  more selected drivers.
- Every selected order appears exactly once in a persisted route.
- Every driver receives a working, date-bound secret link by email.
- A driver can see delivery details in optimized order and open each destination in
  Google Maps.
- A driver can mark any pending stop delivered.
- Completing a stop marks its order fulfilled and updates route progress.
- The link cannot be used after the delivery date.
