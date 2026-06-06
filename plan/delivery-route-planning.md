# Plan: Daily delivery route planning and driver dispatch

## Goal

Add a mobile-first delivery dispatch workflow that:

- Lets a florist optimize today's eligible delivery orders across selected drivers.
- Uses HERE Tour Planning to assign orders and determine stop order.
- Publishes immutable trips into one daily route per driver.
- Emails each external driver one secret, date-bound link on their first assignment.
- Lets drivers navigate each stop with Google Maps and record delivery outcomes.
- Appends later assignments after an explicit return-to-shop stop.
- Gives admins a live view of delivery progress and read-only historical routes.

This feature is separate from the fulfillment calendar. That calendar retains its
current responsibility of enabling and disabling fulfillment dates.

## Resolved product decisions

### Planning and optimization

- Planning lives at `/admin/deliveries`.
- Planning is allowed only for the current date in `Europe/Helsinki`.
- A date picker allows admins to inspect past dates; future dates are disabled.
- Eligible orders are placed, paid, pending delivery orders for today.
- Pickup, unpaid, fulfilled, refunded, and already-dispatched orders are excluded.
- All eligible unassigned orders are preselected; the florist may exclude orders.
- The florist selects one or more active drivers. `Me (florist)` is also selectable.
- If there are no active drivers, `Me (florist)` is preselected as the sole driver.
- If exactly one external driver exists, that driver is preselected.
- More drivers than selected orders is invalid, and every selected driver must
  receive at least one order.
- Drivers have no capacity differences in v1.
- All orders are assumed to have valid persisted coordinates.
- HERE Tour Planning is a deployment/account prerequisite.
- Optimization is synchronous and shown with a LiveView loading state.
- Preview state is held only in LiveView memory and is lost on refresh/navigation.
- Changing selected orders or drivers invalidates the preview.
- Preview is list-only: assignments, ordered stops, route distance, driving time,
  five-minute-per-stop service time, and approximate total duration.
- No departure time or arrival-time estimates are shown. HERE receives a broad
  `08:00-23:59 Europe/Helsinki` nominal shift as an optimization boundary.
- Routes start at the shop and do not return after the final delivery.
- Optimize primarily for balanced completion time, then total travel time.
- Publishing is explicit through `Publish and email drivers`.
- Publication is atomic; email jobs are enqueued only after the transaction commits.
- HERE failures or unassigned jobs block preview/publication. There is no fallback.

### Daily routes and supplemental trips

- A driver has one daily route and one secret link per delivery date.
- A daily route may contain multiple immutable trips published during the day.
- An order may belong to only one published trip.
- New orders arriving later can be optimized as a supplemental batch.
- Existing trips and stop order are never recalculated.
- For each selected driver with earlier trips, append:
  1. A return-to-shop stop, including distance, duration, and Google Maps link.
  2. The newly optimized delivery trip starting at the shop.
- Every later supplemental assignment appends another return-to-shop stop and trip.
- Supplemental optimization includes travel from the driver's final existing stop
  back to the shop when comparing added work across selected drivers.
- Supplemental trips are shown immediately, but are not technically locked until
  earlier work is complete.
- An external driver receives email only on their first assignment that day.
- A driver newly added in a supplemental batch receives their first daily-link email.
- Existing driver pages update through PubSub and show an `Additional trip assigned`
  banner. Supplemental assignments do not send another email.

### Driver access and route UI

- External drivers do not authenticate.
- Anyone holding a high-entropy secret URL may access the route until day-end.
- Store only a SHA-256 token hash; the raw token exists only in the generated URL.
- Tokens are unique per driver and date and expire at midnight in
  `Europe/Helsinki`.
- At expiry, subsequent updates are rejected and an open page becomes an expired
  state. Historical records remain intact.
- The page heading shows the driver name and today's date.
- The florist route uses the same route UI under authenticated admin access and does
  not receive a secret token or email.
- Other admins may open any florist or driver route from the monitoring page.
- Show the full ordered day: pending, delivered, failed, refunded/cancelled, and
  return-to-shop stops.
- Completed stops remain visible, collapsed and clearly marked.
- Failed stops remain visible in their original position and may be retried.
- A refunded order becomes `Cancelled - do not deliver`; it is skipped without
  re-optimizing remaining stops.
- Each delivery shows:
  - Order reference.
  - Recipient name and tap-to-call phone number.
  - Full address and delivery instructions.
  - Card message.
  - Product variant names and quantities, without prices.
  - Approximate distance and driving time from the previous stop.
  - A Google Maps destination link using the device's current location as origin.
- Return-to-shop stops have a Google Maps link and no completion action.
- There is no route-start action, GPS tracking, offline mode, whole-route Google
  Maps link, printing workflow, or customer notification in v1.

### Outcomes and proof photos

- `Record outcome` opens a daisyUI-styled native `<dialog>`.
- The dialog supports:
  - Delivered: method is required (`Handed to recipient`, `Left in a safe place`,
    `Other`).
  - Failed: reason is required (`Recipient unavailable`, `Could not access address`,
    `Could not find address`, `Recipient refused delivery`, `Other`).
  - `Other` requires a note.
  - Note and one proof photo are otherwise optional.
- The photo picker supports preview, removal, and replacement before submission.
- Accept JPEG, PNG, HEIC, and WebP up to 20 MB.
- Submitted attempts are immutable.
- A successful attempt immediately marks the order fulfilled.
- A failed attempt leaves the order pending and does not count toward route
  completion.
- Failed attempts preserve timestamp, reason, note, and optional photo; a later
  successful retry creates another attempt.
- Drivers see the latest failed-attempt details when retrying, but not the submitted
  photo.
- Florists can record delivered or failed outcomes on a driver's behalf using the
  same form. Record the acting admin and that the attempt was admin-entered.
- A route is complete automatically when every delivery is fulfilled or skipped due
  to refund; failed or pending stops prevent completion.
- Attempt notes and photos are internal in v1.

### Driver and photo administration

- Add an AshAdmin-managed `Driver` resource with:
  - Name.
  - Unique email.
  - Preferred language using the app's supported locales.
  - Active/inactive status.
- Drivers cannot be deleted; deactivation preserves history and prevents new
  assignments.
- Existing assignments and links remain usable if a driver is later deactivated.
- Store original photos unchanged on a persistent local filesystem volume shared by
  Phoenix (read/write) and imgproxy (read-only).
- Store relative object paths and metadata in Postgres.
- Photos are retained indefinitely.
- Admin photo display uses short-lived signed imgproxy URLs; raw filesystem paths are
  never public.
- The driver email and route page use the driver's preferred language.

### Rescheduling

- Failed deliveries remain part of their original route until that link expires.
- They are not rolled forward automatically.
- Add `Reschedule delivery` on the admin order detail page for paid, pending delivery
  orders that are not assigned to an active route.
- Rescheduling changes only `fulfillment_date`; coordinates, recipient data,
  instructions, and prior attempt history remain unchanged.
- Once rescheduled to a later date, the order becomes eligible when that date is
  today.
- Customer notification for rescheduling is outside scope.

## Proposed domain model

Place delivery-dispatch resources in `Edenflowers.Store` unless implementation
reveals a clearer existing domain boundary.

### `Driver`

- `id`
- `name`
- `email` (`:ci_string`, unique)
- `preferred_locale`
- `active` (default `true`)
- timestamps
- AshAdmin enabled; destroy actions omitted.

### `DeliveryRoute`

One record per assignee and delivery date.

- `id`
- `delivery_date`
- `assignee_type`: `driver | admin`
- nullable `driver_id`
- nullable `admin_user_id`
- `token_hash` (external drivers only)
- `first_published_at`
- `first_email_queued_at`
- timestamps

Constraints:

- Unique `(driver_id, delivery_date)` when assigned to a Driver.
- Unique `(admin_user_id, delivery_date)` when assigned to a florist.
- Exactly one assignee kind must be populated.
- Token hashes are unique and never returned through normal reads.

### `DeliveryTrip`

An immutable published optimization result appended to a daily route.

- `id`
- `delivery_route_id`
- `batch_id`
- `sequence` within the daily route
- route totals: distance, driving duration, service duration
- `published_at`
- timestamps

### `DeliveryBatch`

Represents one atomic publication across one or more drivers.

- `id`
- `delivery_date`
- `published_by_user_id`
- `published_at`
- timestamps

This gives the admin page one object for a publication while each driver receives a
separate trip.

### `DeliveryStop`

Persist the exact published sequence.

- `id`
- `delivery_trip_id`
- `order_id`
- `sequence`
- leg distance and duration from the preceding stop/shop
- timestamps

An order has at most one delivery stop while its assignment is active. Do not model
return-to-shop as an order stop: derive it between consecutive trips, while persisting
the return leg metrics either on the later trip or in dedicated return-leg columns.

### `DeliveryAttempt`

- `id`
- `delivery_stop_id`
- `outcome`: `delivered | failed`
- delivered method or failure reason
- note
- `recorded_at`
- actor kind: `driver_link | admin`
- nullable `recorded_by_user_id`
- photo path, media type, original filename, byte size
- timestamps

Attempts are append-only. The action creating a delivered attempt and marking the
order fulfilled must run in one transaction.

## Implementation plan

### 1. Add dispatch resources and migrations

- Add `Driver`, `DeliveryBatch`, `DeliveryRoute`, `DeliveryTrip`, `DeliveryStop`, and
  `DeliveryAttempt` Ash resources.
- Register them in `Edenflowers.Store`.
- Define relationships, identities, constraints, code interfaces, admin labels, and
  scoped policies.
- Add read actions for today's eligibility, route monitoring, historical routes,
  token lookup, and attempt history.
- Add transactional actions for publishing a batch and recording outcomes.
- Generate and review Ash migrations/resource snapshots.

Verification:

- Resource tests cover uniqueness, assignee invariants, immutable attempts, one-order
  assignment, active-driver filtering, and admin/secret-link authorization.

### 2. Extend the order lifecycle safely

- Add a dispatch eligibility read action filtered to:
  - `state == :placed`
  - `payment_status == :paid`
  - `fulfillment_status == :pending`
  - `fulfillment_method == :delivery`
  - `fulfillment_date == today`
  - no active/published stop assignment
- Add an internal action that marks fulfilled as part of successful attempt creation.
- Add a guarded reschedule action accepting only `fulfillment_date`.
- Prevent address changes after an order is assigned to a published stop.
- Expose refunded orders to route reads as cancelled/skipped without changing route
  sequence.
- Keep the current admin `mark_fulfilled` action unless later consolidation is safe;
  route outcomes should use their own transactional orchestration.

Verification:

- Policy/action tests cover eligibility, successful and failed attempts, refund
  presentation, address lock, and rescheduling restrictions.

### 3. Add a dedicated HERE Tour Planning adapter

- Keep current geocoding/routing functions intact.
- Add a separate behaviour and implementation, for example
  `Edenflowers.HereTourPlanning`.
- Input is domain-oriented: selected orders, selected assignees, shop coordinates,
  five-minute service duration, nominal shift, and any return-to-shop cost needed for
  supplemental balancing.
- Build the HERE v3 problem with one equivalent vehicle per selected assignee and an
  open-ended shift starting at the shop.
- Configure costs to favor minimizing the longest route, then travel time.
- Parse the response into a stable internal preview struct containing assignment,
  sequence, leg metrics, and totals.
- Reject duplicate, missing, unknown, or unassigned job IDs.
- Use the existing API key configuration if enabled for Tour Planning.
- Keep transport and response parsing behind the behaviour for Mox tests.

Verification:

- Contract tests use representative HERE fixtures for one driver, multiple drivers,
  balanced assignment, and malformed/unassigned responses.

### 4. Implement the publication transaction

- Introduce a dispatch service/action that receives a validated preview plus selected
  order/driver IDs.
- In one database transaction:
  - Create the `DeliveryBatch`.
  - Find or create each driver's daily `DeliveryRoute`.
  - Generate a high-entropy raw token only for a new external route and persist its
    SHA-256 hash.
  - Append one immutable `DeliveryTrip` per assigned driver.
  - Persist ordered stops and all leg/route metrics.
  - Persist return-to-shop leg metrics for supplemental trips.
- Return raw tokens only for newly created external routes so callers can build email
  URLs; never persist or log them.
- After commit, enqueue one Oban email job per newly created external route.
- Publish route/batch events through Phoenix PubSub after commit.

Verification:

- Transaction tests prove all-or-nothing publication, one daily route per assignee,
  no duplicate order assignment, supplemental append order, and no repeated email for
  an existing daily route.

### 5. Add driver route email

- Add a localized email template containing driver name, delivery date, stop count,
  approximate totals, and the secret link.
- Add an idempotent Oban worker keyed by daily route ID.
- Queue it only for the first external assignment of that date.
- Reuse the app's existing mail sender configuration and email conventions.

Verification:

- Worker tests cover locale selection, URL construction, first-assignment behavior,
  and retry idempotency.

### 6. Build `/admin/deliveries`

- Add a top-level admin route and navigation item.
- Today view:
  - Eligible unassigned orders, preselected.
  - Active driver selector plus `Me (florist)`.
  - Remaining-stop counts beside drivers with existing routes.
  - Optimize action and loading/error state.
  - In-memory list preview grouped by driver.
  - Explicit publication action.
  - Published routes and full ordered progress, including derived return-to-shop
    entries.
- Past-date view:
  - Read-only batches, routes, trips, stops, outcomes, attempt history, and photos.
- Subscribe to dispatch and attempt PubSub topics for live progress.
- Show `Open my deliveries` when the current admin has a route today.
- Allow admins to open any route and record outcomes on a driver's behalf.

Verification:

- LiveView tests cover default selections, invalid driver/order counts, preview
  invalidation, HERE errors, publication, supplemental batches, history, and live
  updates.

### 7. Build the shared mobile route UI

- Add a public LiveView route using the raw token in the URL.
- Hash the presented token and perform constant-time matching through a token lookup
  action.
- Validate `delivery_date == store_today()` on mount and every mutating event.
- Add an authenticated admin route for florist and monitoring access.
- Render both routes through shared components/state-loading functions.
- Subscribe to the daily route PubSub topic and append supplemental trips live.
- Render one ordered list with derived return-to-shop rows between trips.
- Build current-location Google Maps destination URLs by omitting an explicit origin.
- Use daisyUI classes around a native `<dialog>` for outcome forms.

Verification:

- LiveView tests cover valid/invalid/expired tokens, midnight mutation rejection,
  complete list rendering, Google Maps URLs, route completion, retry display, and
  supplemental-trip updates.

### 8. Implement delivery attempts and uploads

- Configure `allow_upload/3` for one file, 20 MB, and accepted media types.
- Preview, cancel, and replace the upload before form submission.
- On confirmation:
  - Validate outcome-specific fields.
  - Consume the temporary upload.
  - Write the original to a configured persistent-volume root using a generated,
    non-user-controlled path.
  - Create the immutable attempt.
  - For delivered outcomes, mark the order fulfilled in the same transaction.
- If database persistence fails after file creation, remove the orphaned file.
- Publish route progress after commit.
- Add a small storage behaviour so filesystem work is testable.
- Add signed imgproxy URL generation for authenticated admin photo views only.
- Document runtime variables and volume mounts for Phoenix and imgproxy.

Verification:

- Tests cover type/size limits, replacement, path safety, orphan cleanup, immutable
  evidence, failed retry history, admin attribution, and signed photo URLs.

### 9. Add order-detail rescheduling and route history

- Add `Reschedule delivery` to admin order detail for eligible pending deliveries.
- Block it while assigned to today's active route.
- Show delivery-attempt history and proof photos on the order detail page.
- Preserve prior route/trip context when the order is later dispatched again.

Verification:

- LiveView tests cover action visibility, guarded updates, preserved delivery data,
  and historical attempts.

### 10. Localization, observability, and final verification

- Use Gettext sigils for all driver emails, public route UI, admin flashes, dialogs,
  errors, and status labels.
- Add structured logging around HERE calls and batch publication without tokens,
  recipient details, notes, or photo paths.
- Add telemetry or log timing for synchronous optimization.
- Run:

```sh
source .env
mix format
mix compile --warnings-as-errors
mix test
mix precommit
```

## Suggested implementation sequence

1. Resources and migrations.
2. Eligibility, attempt, fulfillment, and reschedule actions.
3. HERE behaviour, adapter, fixtures, and preview structs.
4. Atomic publication and email worker.
5. Admin planning/monitoring page.
6. Public and authenticated mobile route UI.
7. Outcome dialog and filesystem uploads.
8. Order-detail history/rescheduling.
9. Localization, deployment documentation, and full regression pass.

## Deployment prerequisites

- HERE account/API key with Tour Planning v3 access.
- Persistent filesystem volume for proof photos.
- Phoenix mount with read/write access.
- imgproxy mount of the same directory with read-only access.
- Runtime configuration for:
  - Proof-photo storage root.
  - imgproxy source mapping/signing settings.
  - Public application URL used in driver emails.
- HTTPS for secret driver links and browser camera/file uploads.

## Explicitly out of scope

- Driver authentication or accounts.
- WhatsApp delivery.
- Driver schedules or availability calendars.
- Vehicle capacities or heterogeneous vehicles.
- Delivery time-window UI, though the model/API adapter should leave room for it.
- GPS, background tracking, or mid-route re-optimization.
- Automatic changes to already published stop order.
- Offline/PWA support.
- Customer delivery notifications or customer access to proof.
- Signatures, recipient confirmation, or multiple photos per attempt.
- Dedicated route maps or whole-route Google Maps navigation.
- Draft persistence, cancellation/replacement workflows, email-status dashboards, or
  resend controls.
- Admin cancellation/postponement outcomes.
- Automatic next-day rollover of failed deliveries.

## Principal risks

- HERE objective tuning may not perfectly express “minimize longest route, then total
  time”; validate output against realistic Vaasa delivery sets before relying on it.
- HEIC display support depends on imgproxy's build and codecs even though originals
  can be stored unchanged.
- Secret URLs are bearer credentials. Avoid token logging and referrer leakage, use
  HTTPS, and set an appropriate `Referrer-Policy`.
- Local proof storage requires durable backups; indefinite retention makes volume
  loss a business-data loss.
- Publication must not hold a database transaction open during the HERE request.
  Optimization happens first; only persistence is transactional.
