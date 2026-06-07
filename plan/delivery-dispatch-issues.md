# Delivery dispatch — implementation issues

Tracer-bullet slices for the v1 delivery dispatch feature. Source spec:
[delivery-dispatch-core-requirements.md](./delivery-dispatch-core-requirements.md).

Each slice cuts end-to-end (schema → Ash actions → LiveView/UI → tests) and is
demoable on its own. The optimizer's principal risk is isolated into an early HITL
spike (slice 3) so the rest builds against a deterministic fake in parallel.

## Architecture decisions (shared across slices)

These were settled in design and apply to every slice below:

- Delivery state lives in **new resources** (`Driver`, `Route`, `RouteStop`). `Order`
  stays sealed; it changes only via the existing `mark_fulfilled` bypass. No delivery
  relationship is added to `Order` — eligibility excludes already-published orders by
  querying from the `Route`/`RouteStop` side.
- `RouteStop` **snapshots** recipient/address/instructions/card/products and leg
  metrics at publish; only the order's cancellation/refund status is read live.
- A stop holds a **single current outcome** (retry overwrites); no kept attempt history.
- Status lives on `RouteStop` (`pending | delivered | failed | skipped`); route
  completion is **derived**, never stored.
- Optimizer runs **synchronously in the LiveView**, behind a `TourPlanning` behaviour
  with a config-swappable mock (mirrors `Edenflowers.HereAPI.Mock`). Goal: **minimise
  total driving distance** (cheapest). Objectives are `minimizeUnassigned → minimizeCost`
  with cost weighted to distance; HERE decides how many of the selected drivers to use,
  which falls out of the geometry (open routes). Selected drivers are an availability
  **pool** / upper bound — unused ones get no route. No balancing logic or tuning dial of
  our own — working with the API, not against it.
- The planner is **re-runnable**: each run is an independent global re-solve over
  still-eligible orders and selected drivers. "Wave" is internal terminology only —
  not surfaced in the UI; no continuous auto-reoptimization.
- Each driver has **one stable, unguessable token** (`/d/:token`); the page is
  day-scoped in content and reused across runs and days. No driver accounts.
- Live progress via an Ash `pub_sub` notifier on `RouteStop`, per-route topics.
- Shop (`63.1243488,21.5974075`, Europe/Helsinki) is the **origin only** — not a driver.
- Every route starts at the shop; a later route's "Collect from shop" header is the
  return-to-reload instruction.

---

## 1. Driver resource + admin CRUD + stable token — DONE

**Type:** AFK · **Blocked by:** None · **Status:** complete

### What was built

A new `Edenflowers.Delivery` domain holding the `Driver` resource, plus the admin screen
at `/admin/drivers`. A driver has name, phone, email, preferred language
(`"en-GB" | "sv-FI" | "fi"`), `active?`, and a stable unguessable `link_token` generated
on creation. The admin index at `/admin/drivers` links to dedicated create and edit
LiveView pages and supports deactivate / reactivate, copy-link (client-side
`CopyToClipboard` hook), and regenerate-token. Driver reads are admin-only except
`by_token`, which is a public bypass for the future `/d/:token` page.

### Acceptance criteria

- [x] `Driver` resource with name, phone, email, locale, `active?`, and a unique
      `link_token` generated at creation (`:crypto.strong_rand_bytes` URL-safe, ~128-bit,
      via `Driver.Changes.GenerateToken`).
- [x] Admin LiveView (under the existing `/admin` scope) lists drivers and supports
      create / edit / deactivate; deactivation preserves the row and its history.
- [x] Copy-link button yields the `/d/:token` URL (built from the endpoint URL, since the
      route lands in slice 6); regenerate-token replaces the token and a previously copied
      link stops resolving.
- [x] Deactivated drivers are excluded from `list_active` (the assignment pool) but remain
      in the full list and keep their token/history.
- [x] Tests cover token uniqueness, regeneration invalidating the old token, deactivation,
      the `by_token` public read, and the admin CRUD flow (resource + LiveView tests).

### Notes for later slices

- `Driver.get_by_token/1` returns `{:ok, nil}` (not an error) for an unknown token —
  slice 6's `/d/:token` LiveView should treat `nil` as the not-found case.
- `Driver.list_active` is the availability pool slice 4's driver picker should read.
- The full driver-management UI is translated in English, Finnish, and Swedish with
  non-fuzzy catalog entries.

### User stories

- Admin — managing drivers.

---

## 2. `TourPlanning` behaviour contract + deterministic fake — DONE

**Type:** AFK · **Blocked by:** None · **Status:** complete

### What was built

The optimizer boundary accepts stops and an available driver pool and returns ordered
routes with per-leg and aggregate metrics. `TourPlanning.Solver` resolves the configured
implementation; production and development default to the HERE adapter while tests use
a deterministic fake that returns stable route fixtures without duplicating optimization.

### Acceptance criteria

- [x] `Edenflowers.TourPlanning.Behaviour` with a single `solve/1`
      callback returning `{:ok, [%{driver, ordered_stops, legs, totals}]}` or
      `{:error, :unassigned}` when not every order can be placed.
- [x] Output carries, per stop, the distance/duration from the previous stop, and per
      route the total distance, driving time, and total duration (driving + Σ handling).
- [x] `TourPlanning.Fake` returns deterministic route fixtures for a given input so
      downstream LiveView tests are stable and offline.
- [x] Resolution via `Application.get_env` so prod points at the real adapter (slice 3)
      and tests point at the fake.
- [x] Handling-time-per-stop is a single named config constant.

### User stories

- Enabler for Florist — planning.

---

## 3. HERE Tour Planning adapter + objective spike — DONE

**Type:** HITL · **Blocked by:** #2 · **Status:** complete (validated against live API)

### What was built

The real `Edenflowers.TourPlanning` adapter (synchronous `POST /v3/problems`) and the
`mix eden.tour_planning_spike [drivers]` validation harness, run against today's seeded
Vaasa orders. Each driver maps to a vehicle whose shift starts at the shop with no end
location (open route); each order maps to a delivery job carrying the handling duration.

### Findings (validated)

- HERE requires `capacity` on vehicle types and `demand` on delivery tasks; objective
  names are camelCase (`minimizeUnassigned`, `minimizeCost`, …); `optimizeTourCount`
  needs extra params (not a simple drop-in).
- v1 minimises **total driving distance** via `minimizeUnassigned → minimizeCost` with
  cost weighted to distance. With open routes the driver count falls out of the geometry:
  for the seeded set, HERE chose **2 drivers / 21.4 km** (a single driver was 23.6 km —
  splitting two clusters avoided a long cross-town leg). Deterministic across runs.
- Selected drivers are an availability pool / upper bound; HERE may leave some unused. No
  balancing logic or tuning dial of our own.
- The solution-parsing logic is verified correct against the real response (cumulative
  distance diffs; leg time from stop arrival/departure; handling added to totals).

### Acceptance criteria

- [x] Adapter builds problem JSON, calls `/v3/problems` via `Req`, parses tours into the
      behaviour's output shape, including unassigned jobs → `{:error, :unassigned}`.
- [x] Vehicles start at the shop with no end location; jobs carry handling duration.
- [x] Least-distance objective + driver-count-from-geometry validated against real Vaasa
      orders.
- [x] Failure/non-200 from HERE surfaces as a clean error (no partial result).
- [x] HERE schema + objective strings confirmed against the live API.

### Follow-ups for slice 4

- Selected drivers are an availability pool; the review must handle HERE using fewer
  drivers than selected (unused drivers get no route — this is expected, not an error).

### User stories

- Principal risk (optimizer correctness).

---

## 4. Plan a run: eligibility + driver selection + optimize + review — DONE

**Type:** AFK · **Blocked by:** #1, #2 · **Status:** complete

### What was built

The deliveries planning page at `/admin/deliveries`: it lists today's eligible orders
pre-selected, lets the florist deselect orders and choose available drivers (with the
one-driver default), and on "Optimize" calls the configured `TourPlanning.Solver`
synchronously and renders the proposed routes for review — per driver, ordered stops with
per-leg distance/time and route totals including handling. The draft is ephemeral
(discarded whenever the selection changes, and on leave). If any order can't be placed,
planning is blocked with a message — no partial result.

### Acceptance criteria

- [x] Eligibility read (`Order.eligible_for_delivery`): placed, paid, pending fulfillment,
      delivery method, dated today (Europe/Helsinki), with a geocoded position — all start
      selected. The "not already on a published route" exclusion lands with slice 5 (it
      queries the not-yet-existing `RouteStop`); until then every matching order is eligible.
- [x] Driver picker lists active drivers as an availability pool; if exactly one active
      driver exists it is pre-selected. The optimizer may use fewer drivers than selected
      — unused drivers get no route, which the review shows plainly (not an error).
- [x] "Optimize" runs synchronously with the button disabled and a loading state; result
      assigned to socket only (nothing persisted).
- [x] Review shows per driver: ordered stops, per-leg distance/time, total distance,
      driving time, and total duration (driving + Σ handling). No clock/arrival times.
- [x] `{:error, :unassigned}` blocks the run with an explanatory message; changing
      orders/drivers discards the draft to re-optimize; navigating away discards the draft.
- [x] LiveView tests drive the flow against `TourPlanning.Fake`.

### Notes for later slices

- Slice 5's publish action reads the draft `routes` off the socket and adds the
  published-route exclusion to `Order.eligible_for_delivery` (query from the `RouteStop`
  side, per the shared architecture decision).

### User stories

- Florist — planning.

---

## 5. Publish a run — DONE

**Type:** AFK · **Blocked by:** #4 · **Status:** complete

### What was built

New `Route` and `RouteStop` resources in the `Edenflowers.Delivery` domain, plus a "Publish
run" action on the planning page. Publishing turns the reviewed draft into persisted rows: one
`Route` per driver the optimizer used (carrying `date` + `published_at`), each with ordered
`RouteStop`s that snapshot the order's recipient/phone/address/instructions/card message,
product names + quantities (prices excluded, card excluded from the product list), position,
sequence, and per-leg distance/duration. The whole run is created inside one `Ash.transaction`,
so a failure on any route persists nothing. `Order.eligible_for_delivery` now excludes orders
already on a published route (queried from the `RouteStop` side, keeping `Order` relationship-
free), and the page renders today's published routes above the still-usable planner so a second
run plans only what's left.

### Acceptance criteria

- [x] Publish persists one `Route` per used driver (with `published_at`, `date`, `driver_id`)
      and ordered `RouteStop` rows snapshotting recipient name, phone, address,
      instructions, card message, product names + quantities (no prices), sequence, and
      per-leg distance/duration.
- [x] Publish is atomic — a failure persists nothing.
- [x] Published orders drop out of the eligible set, so a second run plans only what's
      left; published routes render on the page next to the planner.
- [x] A driver can hold more than one route for the day (one per run).
- [x] Tests cover snapshot fidelity and the eligibility-exclusion after publish.

### Notes for later slices

- `RouteStop` already carries the `status` column (`pending | delivered | failed | skipped`,
  default `pending`) and `position` snapshot; slice 6 reads stops for the `/d/:token` page and
  slice 7 overwrites `status` on outcome. `RouteStop.published_order_ids/1` is the eligibility
  exclusion helper; `Route.list_published_for_date/1` loads routes with driver + ordered stops.

### User stories

- Florist — planning (publish).

---

## 6. Driver route page (read-only) — DONE

**Type:** AFK · **Blocked by:** #1, #5 · **Status:** complete

### What was built

The public, no-login `EdenflowersWeb.DriverRouteLive` at `/d/:token`, mounted in its own
slim `:driver` router pipeline that skips the store plugs (cart init, maintenance redirect)
and auth — the unguessable token is the only gate, so reads run with `authorize?: false`
once `Driver.get_by_token/1` resolves a driver. A new driver-scoped read,
`Route.list_for_driver/2`, loads that driver's published routes for today with their ordered
stops. Each route renders as its own ordered list headed by a "Collect from shop" marker;
each stop shows order reference, recipient name, tap-to-call phone, full address, delivery
instructions, card message, product names/quantities (no prices), and per-leg distance/time,
plus a current-location Google Maps directions link. The page forces the driver's preferred
locale (`Localize.put_locale` + the matching Gettext locale), independent of the
browser/session, and shows a clear empty state on a day with no routes.

### Acceptance criteria

- [x] `/d/:token` public LiveView outside the authenticated/admin scope; unknown token →
      not-found page.
- [x] Shows the driver's name, today's date, and every today route as a separate ordered
      list, each headed by a "Collect from shop" start marker.
- [x] Each stop renders all required fields with prices excluded; tap-to-call phone link;
      Google Maps link of the form `…/maps/dir/?api=1&destination=<lat,lng>` (origin
      omitted → current location).
- [x] Page renders in the driver's locale; on a day with no routes it shows a clear
      "nothing to deliver" state.
- [x] Tests cover token resolution, multi-route rendering, locale, and the empty state.

### Notes for later slices

- `Route.list_for_driver/2` is the per-driver day read slice 7 builds outcome recording on;
  the page is keyed by `:token`, so a stop's status update should patch in place per-route.
- New `~t` strings are extracted into the catalogs; fi/sv msgstrs are empty pending translation.

### User stories

- Driver — delivering (view).

---

## 7. Record an outcome

**Type:** AFK · **Blocked by:** #6

### What to build

Outcome recording on the driver page. For each stop the driver records exactly one
current outcome: **delivered** (method: handed to recipient / left in a safe place /
other) or **failed** (reason: recipient unavailable / couldn't access / couldn't find /
refused / other), with an optional note that becomes required when "other" is chosen. A
delivered outcome marks the order fulfilled via the existing `mark_fulfilled` bypass; a
failed outcome leaves the order pending and the stop retryable the same day (retry
overwrites the outcome). Completed stops collapse out of the way.

### Acceptance criteria

- [ ] Delivered requires a method; failed requires a reason; "other" (either side)
      requires a note; note otherwise optional.
- [ ] Delivered sets `RouteStop` status `delivered` and calls `mark_fulfilled` on the
      order; failed sets status `failed`, order stays pending.
- [ ] A failed stop can be retried the same day; the new outcome overwrites the previous
      (no history retained).
- [ ] Completed (delivered) stops collapse but remain visible and clearly marked.
- [ ] `RouteStop` carries an Ash `pub_sub` notifier broadcasting on outcome change to a
      per-route topic.
- [ ] Tests cover each outcome path, the "other"→note rule, retry overwrite, and the
      order being marked fulfilled.

### User stories

- Driver — delivering; Recording an outcome.

---

## 8. Live progress monitoring

**Type:** AFK · **Blocked by:** #5, #7

### What to build

The florist's monitoring view on the deliveries page: for every published route it shows
live progress as drivers record outcomes, subscribing to the per-route `RouteStop`
topics. Each driver shows a copy-link button, and the florist can open any driver's page
to see exactly what the driver sees. Route completion is a derived calculation over the
route's stops. This slice also verifies the re-run flow: planning and publishing a
second run while the first is still in progress.

### Acceptance criteria

- [ ] Monitor subscribes to the per-route topics of today's published routes and patches
      a stop's status in place on broadcast (no full reload).
- [ ] Per-route progress (e.g. delivered/failed/remaining counts) derived from stops;
      route shows complete when every stop is delivered or skipped.
- [ ] Copy-link button per driver; "open driver view" opens the `/d/:token` page.
- [ ] Verified: a second run can be planned and published while the first is live, and
      its routes/progress appear alongside without disturbing the first.
- [ ] Tests cover a broadcast updating the monitor and derived completion.

### User stories

- Florist — handoff & monitoring.

---

## 9. Cancellation "do not deliver" + order-page outcome visibility

**Type:** AFK · **Blocked by:** #7

### What to build

Handle an order cancelled/refunded after its route is published: its stop shows "do not
deliver", is marked `skipped`, and is excluded from blocking route completion, without
re-ordering the rest of the route. Separately, surface delivery outcome on the order
detail page — whether the delivery succeeded or failed, when, and why.

### Acceptance criteria

- [ ] A refunded/cancelled order's stop renders a "do not deliver" banner (live status
      read from the order) and counts as `skipped` for completion.
- [ ] A skipped stop does not block route completion and the rest of the route is not
      re-sequenced.
- [ ] Order detail page shows the current delivery outcome: delivered (method, when) or
      failed (reason, when), or not-yet-attempted.
- [ ] Tests cover the cancel-after-publish path and order-page outcome rendering.

### User stories

- Florist — failed deliveries; Cancellations during the day.

---

## 10. Wire the real optimizer into planning + tune handling time

**Type:** AFK · **Blocked by:** #3, #5

### What to build

Verify production uses the validated HERE adapter and exercise
the full planning → review → publish flow against the real optimizer, tuning the
handling-time constant against observed results. No new behaviour — this is the
integration/rollout of the spiked adapter into the live flow.

### Acceptance criteria

- [ ] Production and development resolve `TourPlanning` to the HERE adapter; tests use
      the fake.
- [ ] A real planning run produces least-distance, plausible routes for a realistic Vaasa set
      end-to-end through publish.
- [ ] Handling-time constant tuned and documented.
- [ ] Optimizer failure/timeout surfaces cleanly in the planning UI (no partial publish).

### User stories

- Principal risk (optimizer integration).

---

## Dependency graph

```
1 ──┬─→ 4 ─→ 5 ─→ 6 ─→ 7 ─┬─→ 8
2 ──┘                      └─→ 9
2 ─→ 3 ───────────────────────→ 10
5 ───────────────────────────→ 10
```

Critical path: 1 → 4 → 5 → 6 → 7 → 8/9, with 2 → 3 → 10 running alongside.
