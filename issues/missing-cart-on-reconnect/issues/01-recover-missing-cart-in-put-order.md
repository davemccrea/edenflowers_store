# Recover from a missing cart in PutOrder instead of raising

Status: ready-for-agent
Type: task

## Problem

`EdenflowersWeb.Hooks.PutOrder.on_mount/4` calls `Orders.get_order_for_checkout!/2` with the `order_id` from the LiveView session. `InitStore` only checks that id on HTTP requests, so a socket that reconnects later can carry an id that no longer reads:

- `purge_abandoned_cart` (03:00 UTC daily) deleted the empty cart while the tab sat open for more than a day.
- The guest placed that order in another tab, so the `:for_checkout` read policy now hides it.

The bang raises `Ash.Error.Invalid` (record not found), LiveView turns it into a `ReloadError` 404, and the browser reloads. `InitStore` then starts a new cart, so the customer loses nothing, but each case logs two errors in ErrorTracker (`/admin/errors`), and both are noise.

Seen once, on `AccountLive`: 2026-10-18 03:40:34 UTC.

## Fix

In `PutOrder`, use the non-bang `get_order_for_checkout`. On not found, `{:halt, redirect(socket, to: <current path>)}` so the HTTP request runs through `InitStore`, which sets up a new cart. `PutCurrentPath` runs before `PutOrder` in the `:public` live session and may already provide the path.

## Acceptance

- A LiveView test mounts a `:public` page with a session `order_id` for an order that has been deleted. It redirects instead of raising.
- The same works for a guest whose session order is `:placed`.
- Mounting with a valid cart behaves as before.

## Comments
