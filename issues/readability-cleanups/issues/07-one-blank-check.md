# Agree on what counts as blank in the admin

Status: ready-for-agent
Type: refactor

## Problem

Three admin LiveViews each define a private `present?/1`, and they disagree:

- `Admin.OrderFormLive`: `is_binary(value) and String.trim(value) != ""`, so whitespace is blank.
- `Admin.OrderDetailLive`: `nil` and `""` are blank, anything else is present, so `"  "` is present. Its `presence/1` builds on it.
- `Admin.DashboardLive`: `nil` is blank, otherwise `String.trim(value) != ""`, which raises on a non-string.

So an order whose Card Message is only whitespace gets an empty card widget on the order page but no card badge on the dashboard.

## What to build

- One helper, available to every admin LiveView (e.g. in `EdenflowersWeb.Admin.Components`, or a small `EdenflowersWeb.Blank` module), with the order form's meaning: only a string with non-whitespace content is present. Keep `presence/1` beside it if `OrderDetailLive` still needs it.
- Remove the three private copies.
- Better still where it applies: trim on the way in (`constraints: [trim?: true]` on the attribute), so the stored value is never whitespace-only and the views only check for `nil`. Decide per field; don't change stored data in this ticket.

## Tests

- The existing suite passes. Add a LiveView test that a whitespace-only Card Message doesn't render the card widget on the order page.

## Acceptance criteria

- [ ] One definition of `present?/1` in the web layer
- [ ] The existing suite passes

## Comments
