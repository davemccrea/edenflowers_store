---
id: TASK-167
title: Settle the Finnish case for Minimossen
status: needs-triage
assignee: []
created_date: '2026-11-01 19:08'
updated_date: '2026-11-01 19:10'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: task
ordinal: 313000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settle which Finnish case the storefront uses for Minimossen, and make every fi string agree.

**Why:** Finnish customers see Minimossen inflected two ways across the site ("Minimossenissa" and "Minimossenilla"), which reads as careless to a native speaker.

The fi catalogues mix two case families:
- Inner locative (-ssa/-sta), the majority: "liikkeessä Minimossenissa" (contact, home, about), "Minimossenissa tai omissa tiloissanne" (courses), "km Minimossenista" (free delivery lines, store page).
- Outer locative (-lla/-lta): "Minimossenilla, %{address}…" (FAQ pickup answer), "Tilauksesi on noudettavissa Minimossenilta %{date}." (order confirmation page, added 2026-11-01).

Stormossen's own Finnish page (https://www.stormossen.fi/minimossen/) uses the outer form in a headline, "Vanha on Minimossenilla uusinta uutta", and calls the place "Kierrätysgalleria Minimossen". One headline is thin evidence; the majority of our copy goes the other way.

Open: which form is right (ask a Finnish speaker, or check more of Stormossen's Finnish copy), and whether "from Minimossen" for pickup and for delivery distance should use the same case. Then follow priv/gettext/README.md for the fi review rules.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Finnish speaker or Stormossen's usage has settled the case for Minimossen, recorded in the priv/gettext/README.md glossary
- [ ] #2 Every fi msgstr that inflects Minimossen uses the settled case
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 19:10

---

The order confirmation page no longer names the place ("Your order will be ready to collect on %{date}."), so its "Minimossenilta" is gone. The FAQ's "Minimossenilla" is now the only outer-locative form.

---
<!-- COMMENTS:END -->
