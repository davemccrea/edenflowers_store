---
id: TASK-95
title: >-
  Check client-side JS attribute and class changes for state that outlives a
  patch
status: done
assignee: []
created_date: '2026-10-22 18:23'
updated_date: '2026-10-22 18:24'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: bug
ordinal: 202000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Find each JS.set_attribute, remove_attribute, add_class and remove_class that can leave the page disagreeing with the server after a LiveView patch, and fix it.

**Why:** LiveView keeps these client-side changes through later patches, and morphdom reuses elements by id, so the page can keep showing a stale state. That is how the store's category underline stuck on the wrong tab (fixed in d1255efb). Checkout uses the same calls to lock the form and disable the pay button, where a stuck state could block a payment.

Calls to check:
- checkout_live.ex: lock_while_paying / unlock_after_paying set and remove inert on the form while paying
- core_components.ex: data-stripe-loading / data-stripe-ready disable and enable #payment-button; welcome-back removes hidden on mount
- translation_fields.ex: admin language tabs toggle hidden, tab-active and aria-selected
- layouts.ex: client-error hidden on connect/disconnect; shy-header--hidden class

Open: which of these can meet a patch that re-renders the element with a different state, and whether each needs a fix or is safe as is.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each listed call is marked safe or fixed, with the reason in the notes
- [x] #2 Any fixed call is checked in a browser across the patch that used to break it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Reviewed every call; none needs a fix. The store tabs broke because the server owned the state and a patch from outside the tabs changed it. None of these has that shape.

- checkout_live.ex lock_while_paying / unlock_after_paying: safe. Sticky inert is the point (it must survive re-renders while paying). Every failed pay path unlocks: over stock and update_amount errors push stripe:ready, and the hook calls stripeReady on card, confirm and init errors. Success leaves via Stripe's redirect. The client_secret: nil pay clause can't run while locked, because the form only renders with a client secret.
- core_components.ex #payment-button disabled: safe. The server always renders disabled, and the hook is the only thing that enables it, so the sticky removal is what keeps it usable across re-renders.
- core_components.ex welcome-back: only a doc example.
- translation_fields.ex language tabs: safe. Deliberately sticky so the open tab survives typing. The server always renders English, and product_form_live and course_form_live never patch between records.
- layouts.ex client-error and shy-header: safe. Driven only by connection events and the HotFxShyHeader hook, never by server state.

AC 2: nothing was fixed, so there was nothing to check in a browser.
<!-- SECTION:NOTES:END -->
