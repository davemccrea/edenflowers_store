---
id: TASK-168.13
title: Manage standalone invoices from the admin
status: done
assignee:
  - '@invoice-model'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:22'
labels: []
dependencies:
  - TASK-168.9
  - TASK-168.10
  - TASK-168.11
references:
  - lib/edenflowers_web/features/admin/invoice_drawer.ex
  - lib/edenflowers_web/features/admin/invoice_controller.ex
  - lib/edenflowers_web/router.ex
parent_task_id: TASK-168
type: feature
ordinal: 327000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie needs one place to create bespoke invoices, see what is owed and record bank transfers.

Add an admin navigation entry and invoice list/detail/form workflow using the existing admin conventions. Enter buyer, optional business/reference details, language, relevant dates and editable billed lines; preview totals before issue. Expose issue, send/download, resend/remind, record/reverse payment and full unpaid credit operations with clear states. For paid/part-paid invoice corrections, explain that Jennie should contact the accountant; do not offer a workaround that changes the payment history. Wedding invoices use this same ordinary form.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Admin can create/edit a draft, issue it and email/download the invoice with no purchase selection
- [x] #2 The form calculates totals and VAT from line inputs and shows validation errors before issuance
- [x] #3 The list/detail shows draft, unpaid, overdue, paid and credited states and supports the appropriate actions with payment history
- [x] #4 Non-admins cannot access invoice management or document downloads; email failure is visible and retryable
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Extend existing admin navigation/components with standalone invoice list and draft/detail form. Preview exact totals through InvoiceFinancials; invoke domain actions for issue/send/credit/payment/reversal. Keep editable and issued content distinct, show payment history and accountant exception, secure all routes. Verify meaningful LiveView interactions, document access and failure/retry states; extract admin strings with coordinated gettext ownership.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added invoice navigation/register and standalone draft/detail workflow. Editable buyer/company/reference, dates/language, add/remove billed lines and VAT preview support decimal commas. Save and issue are distinct, issued details/PDF links frozen, issue failure preserves one editable draft. Issued screens expose email/reminders with visible failure/retry, payments/reversals with history, full unpaid credit and accountant exception for paid/part-paid corrections. Resource :admin_list provides sorted paginated invoice register. PDF route now /admin/invoices/:id/pdf; management remains protected by admin LiveView hooks and controller actor checks. Verification: 17 focused tests passed (10 new LiveView interaction tests plus 7 model/financial/concurrency tests), mix format --check-formatted passed, mix assets.build passed, gettext.extract --merge --no-fuzzy + gettext.check + gettext.stats passed. Reviewed rendered draft at desktop 1440 and mobile 390 pixels with no horizontal overflow; screenshots in tmp/invoice-admin-desktop.png and tmp/invoice-admin-mobile.png. Impeccable mechanical scan found only pre-existing layouts.ex 10px advisory, no new UI findings. New admin translations may fall back to English, permitted by translation policy; no native-language approval claimed. Preserved unrelated catalog edits and cleared inaccurate automatic fuzzy matches only for new invoice UI entries.
<!-- SECTION:NOTES:END -->
