---
id: TASK-133.4
title: >-
  Remove Custom Order deletion and use cancellation with existing Cinder
  filtering
status: done
assignee: []
created_date: '2026-10-25 22:24'
updated_date: '2026-10-26 05:35'
labels: []
dependencies:
  - TASK-133.2
references:
  - lib/edenflowers/orders.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/orders/order/admin.ex
  - lib/edenflowers/orders/order/checkout.ex
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/order_detail_components.ex
  - lib/edenflowers_web/features/admin/orders_live.ex
  - lib/edenflowers_web/features/admin/overview_live.ex
  - lib/edenflowers/accounting/monthly_report.ex
parent_task_id: TASK-133
type: refactor
ordinal: 259000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie can remove a mistaken Custom Order from her working list by cancelling it and using the existing Cinder view. The default Still to do view already excludes cancelled orders; adding archive state/actions would duplicate that behaviour and create more business rules to maintain.

Remove the normal :delete_custom action/domain interface, Delete control, permission/log/dispatch references and genuinely unused deletion-only helpers after searching all callers. No normal app path should hard-delete a placed order. Keep existing explicit cancellation, stock return, money/refund/kept choices, audit history and customer-notification controls. Do not add another cancellation/settlement orchestration action.

Do not add Archive, archived_at, archiveable?, a hidden/deleted flag, an archive log event or an Archived view. Verify rather than replace the current Cinder Still to do default and All orders access. Cancelled Custom Orders remain findable through All orders, ordinary search and direct details; these are not permanent hidden records. Existing Cinder state/filter semantics should be reused, not supplemented with resource-wide base filters.

Preserve order ID/reference, lines, VAT snapshots, all Payments/refunds/reversals and PaperTrail history. A cancelled order's new financial obligation after late money must still appear in Overview/settlement views despite exclusion from the working list. Customer history, receipts, payment/refund relationships, accounting and revenue remain intact. Use shared late-money handling from TASK-133.2.

This change does not require a zero-Balance guarantee before a table can filter out cancellation: working-list visibility and financial attention are separate. It also leaves the existing old empty-store-cart purge unchanged. Do not create an archive migration or block finding cancelled orders in global admin search.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No normal application action or UI permits hard deletion of a placed Custom/Online Order; obsolete Delete domain/policy/dispatch references and genuinely unused destructive-only helpers are removed.
- [x] #2 Existing cancellation/settlement returns stock and accounts for money through the current explicit actions, retaining identity, lines, VAT snapshots, Payments/reversals and full history.
- [x] #3 The current Cinder Still to do default excludes cancelled orders, while All orders, ordinary search and direct details still find them; no archive/hidden schema, action, eligibility or special view is introduced.
- [x] #4 Late payment/refund callbacks still find cancelled orders and expose new obligations in Overview/settlement even when the working table excludes them; customer history, receipts, revenue and accounting remain correct.
- [x] #5 Tests cover removed deletion paths, retained cancelled records/history, default versus All/search/direct access, late financial attention and unchanged empty unused store-cart cleanup.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Search Delete action/UI/domain/log/helper callers, replace the product instruction with existing cancellation/settlement and remove the hard-delete operation. Add preservation assertions. Verify Cinder default/All/search/direct access and financial attention with a late payment through the shared code. Leave normal cancelled histories and accounting reads untouched. Remove unused destructive helpers only after caller checks; no archive migration, state, action or new view.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed Custom Order delete action/interface/calculation/policy/pubsub/UI/handler and deletion-only validation, log-erasure helper and payment-in-progress exception. Simplified shared cancellation now deletion orchestration is gone. Existing sole order destroy action is empty old store-cart cleanup; added the same eligibility filter to the action so it cannot be called directly to delete placed/active carts. Adapted stale-session fixture to an old eligible cart. Tests retain cancelled identity/lines/VAT/log/payment reversal history and stock exactly once; All orders/search/global search/direct links retain cancelled Custom Orders, and actual late payment appears in Overview independent of working-list filter. Targeted tests passed. Full precommit lint/migration checks passed and exposed only the now-fixed stale-session fixture. Updated seeded course example to accepted unpaid booking. No archive state/schema/view or production operation.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 04:45

---

Supersedes this subtask's earlier Archive feature. User explicitly chose the existing Cinder filter instead: no archive schema, action, eligibility rule, audit event or Archived view.

---

author: @claude
created: 2026-10-26 04:46

---

Supersedes the original Archive feature entirely. The user chose existing Cinder filtering instead. Cancelled orders remain in All orders/search/direct history; no Archive action, marker, eligibility, Archived filter or archive-specific migration is authorized.

---
<!-- COMMENTS:END -->
