# Give the shop's day and time one home

Status: ready-for-agent
Type: refactor

## Problem

`Edenflowers.Expressions.HelsinkiToday` exists so Elixir code and Ash expressions agree on the shop's date, but only a handful of modules use it (`StepToScheduledDate`, `CancelOpenOccurrences`, `Subscription`, `PushNewOrder`, `PromotionFormLive`, `AccountLive`). Everywhere else repeats `"Europe/Helsinki"` inline, in four forms:

- `DateTime.now!("Europe/Helsinki") |> DateTime.to_date()`: `FulfillmentDateNotPast`, `ReserveSeats`, `SetNewsletterDefaults`, `Promotion` (`:today` argument default), `SendNewsletterPromoEmail`, `Admin.CoursesLive`, `Admin.OrderDetailLive` (`store_today/0`), `Admin.OrdersLive`.
- `DateTime.now!("Europe/Helsinki")` for the wall-clock time: `Availability`, `CreateOccurrence`, `Admin.OrderFormLive`, and the footer year in `Layouts`.
- A module attribute `@timezone "Europe/Helsinki"`: `Admin.FulfillmentsLive`, `Admin.DashboardLive`, `AccountLive`, `DatePicker` (`@default_timezone`).
- A raw SQL fragment `(now() AT TIME ZONE 'Europe/Helsinki')::date` in three `Course` filters and calculations, where `helsinki_today()` would do.

Shifting to Helsinki for display (`Format`, `Admin.Components`, `OrderDetailLive`, `SalesSummary`, `FulfillOnDate`) is a third use of the same constant.

## What to build

- One module, e.g. `Edenflowers.ShopTime`, with `timezone/0`, `now/0` (a Helsinki-zoned `DateTime`) and `today/0`. `HelsinkiToday` keeps the Ash expression and delegates `today/0` to it, or `ShopTime` takes over and the expression module calls it.
- Every inline `"Europe/Helsinki"` above uses it. `Format.datetime/3`'s default argument reads `ShopTime.timezone()`.
- `Course`'s three SQL fragments become `helsinki_today()`.
- No behaviour change, except `Course` now evaluating "today" when the query is built rather than in Postgres. Both are Helsinki's date, so they agree.

## Tests

- The existing suite passes. Tests that freeze or pass `today` keep doing so.

## Acceptance criteria

- [ ] `"Europe/Helsinki"` appears only in `ShopTime` (and config, if any)
- [ ] The existing suite passes

## Comments
