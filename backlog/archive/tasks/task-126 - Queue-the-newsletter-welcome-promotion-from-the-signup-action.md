---
id: TASK-126
title: Queue the newsletter welcome promotion from the signup action
status: done
assignee: []
created_date: '2026-10-25 14:15'
updated_date: '2026-10-25 16:46'
labels:
  - spec
  - customers
  - developers
dependencies: []
references:
  - lib/edenflowers/accounts/user.ex
  - lib/edenflowers_web/components/newsletter_signup.ex
  - lib/edenflowers/orders/changes/upsert_user_and_assign_to_order.ex
  - lib/edenflowers/pricing/workers/send_newsletter_promo_email.ex
priority: medium
type: refactor
ordinal: 248000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Promotional newsletter signup records the opt-in and queues its welcome/promotion email through one Accounts action, regardless of the entry point.

**Why:** The footer announces that a code is on its way after separately subscribing and enqueueing, while checkout maintains another opt-in-and-queue sequence. Callers can forget the follow-up or silently ignore an enqueue failure.

Review evidence: User.:subscribe_to_newsletter only upserts the preference. NewsletterSignup separately calls SendNewsletterPromoEmail.enqueue and ignores its result. Orders.Changes.UpsertUserAndAssignToOrder separately updates the preference and enqueues that worker after the order transaction.

Give promotional signup an action-owned queueing hook and use it from footer and checkout. Reuse the existing worker and job uniqueness behaviour, including returning-subscriber wording. Keep ordinary account preference changes separate if those intentionally send no welcome email. Preserve checkout's policy that a failed newsletter opt-in does not fail an otherwise valid order; make the signup failure visible/logged appropriately instead.

Triage the distinction between promotional signup and preference toggling, and confirm failure handling. Do not make every newsletter preference update send a promotion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calling the promotional signup action directly records the opt-in and queues the existing welcome/promotion worker without a caller-owned enqueue step.
- [x] #2 Footer and checkout use the same domain signup operation; routine preference updates and unsubscribes do not accidentally send welcome emails.
- [x] #3 Queue insertion failures are handled explicitly: the footer does not falsely promise an email, while a failed optional signup does not roll back the customer order.
- [x] #4 Regression tests cover direct signup, footer/checkout callers, repeat signup/job uniqueness and failure handling without changing the existing returning-subscriber rules.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Triage (2026-10-25): :subscribe_to_newsletter inserts the SendNewsletterPromoEmail job in an after_action inside its transaction, so an enqueue failure rolls back the opt-in. Footer and checkout both call it; checkout still runs it after the order commits and only logs a failure. The account page toggle (:update) stays promo-free. The footer's put_flash never reached the page (a component's flash only propagates on navigation), so its error now shows inline.
<!-- SECTION:NOTES:END -->
