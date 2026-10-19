---
id: TASK-59
title: Admin email gallery with localized scenario previews
status: ready-for-agent
assignee: []
created_date: '2026-10-19 06:39'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 125000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Give Jennie a read-only admin gallery to review every meaningful variant of outgoing email text in English, Swedish and Finnish.

**Why:** Email wording errors are hard to spot without placing orders in each state. A gallery makes outgoing copy and translations reviewable together, including cases such as a non-gift delivery incorrectly saying “Your order for Sara”.

## Agreed design
Use the existing admin shell, select inputs and cards. Put email-type and preview-language selectors at the top, followed by matching scenario cards grouped by email type. Switching language preserves the selected email type and scenario set, independently of the admin interface language. Do not introduce Cinder or an Ash/database resource solely for this fixed catalogue.

Include all outgoing email types: orders, subscriptions, courses, wedding enquiries, newsletters, authentication and internal error alerts. The current inventory is 15 EEx templates plus the inline error alert in lib/edenflowers/email.ex; verify the inventory during implementation.

Define named scenarios with stable identifiers and realistic fictional data. Cover every copy-changing branch, including personalized/generic greetings, optional sections, payment/refund states, pluralization and fulfillment states. Use meaningful scenarios rather than the Cartesian product of every field. Include non-gift orders with a populated recipient name, both with and without a delivery photo; cover gifts and pickup too. Inspect all templates for the full branch inventory.

Each card shows a descriptive title (for example “Delivery confirmation — gift order”), the relevant scenario conditions, the actual subject and plain-text body, and compact sender/recipient/CC/BCC and attachment name/type metadata where applicable. Render through the production email builders; establish locale as production callers do, including translated supplied content where needed. Fixed-language operational emails should remain faithful to their actual output.

Previews must never send email, create real orders, fetch delivery photos or generate receipt PDFs. Represent attachment metadata using fictional sample attachments or explicit metadata where attachments are normally added outside the builder. Escape rendered text and preserve whitespace. Reuse existing admin authorization and navigation patterns.

Keep the catalogue in code. Add a runnable coverage check that every email type has a preview, and document that template or conditional-copy changes must update the scenarios. Do not attempt to infer meaningful permutations automatically from template source.

## Code pointers
- lib/edenflowers/email.ex
- lib/edenflowers/email/templates.ex and lib/edenflowers/email/templates/
- lib/edenflowers_web/router.ex (admin LiveView session)
- lib/edenflowers_web/components/layouts.ex (admin navigation)
- lib/edenflowers_web/components/core_components.ex (select inputs)

Scope is read-only inspection; copy editing remains a code change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An admin-only gallery is reachable from admin navigation and uses existing admin shell, select inputs and cards.
- [ ] #2 Email-type filtering and English (en-GB), Swedish (sv-FI), and Finnish (fi) preview selection work independently of the admin interface locale; changing language preserves the current type/scenarios.
- [ ] #3 Every outgoing email type, including authentication, newsletter and internal alerts, has named scenarios covering its copy-changing branches with fictional data.
- [ ] #4 Each scenario displays a descriptive title, relevant conditions, production-rendered subject and escaped whitespace-preserving body, plus compact envelope and attachment metadata.
- [ ] #5 Non-gift deliveries with populated recipient names render generic delivery wording in both normal and photo confirmations; named gifts retain recipient wording and pickup scenarios show collection wording.
- [ ] #6 Previewing performs no email delivery, real order creation, remote photo fetching or receipt-PDF generation.
- [ ] #7 Automated checks verify email-type coverage, admin access control, filtering/locale behavior and representative branch rendering; documentation requires scenario updates when conditional email copy changes.
<!-- AC:END -->
