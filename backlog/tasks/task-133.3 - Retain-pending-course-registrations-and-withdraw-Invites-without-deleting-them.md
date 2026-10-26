---
id: TASK-133.3
title: Replace course Invites with confirmed manual bookings payable at the course
status: ready-for-agent
assignee: []
created_date: '2026-10-25 22:24'
updated_date: '2026-10-26 04:46'
labels: []
dependencies:
  - TASK-133.2
references:
  - lib/edenflowers/courses.ex
  - lib/edenflowers/courses/course_registration.ex
  - lib/edenflowers/courses/course_registration/admin.ex
  - lib/edenflowers/courses/course_registration/checkout.ex
  - lib/edenflowers/courses/course_registration/changes/price_booking.ex
  - >-
    lib/edenflowers/courses/course_registration/changes/send_confirmation_email.ex
  - lib/edenflowers/courses/course_registration/changes/send_reminder_email.ex
  - lib/edenflowers_web/features/admin/course_booking_drawers.ex
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers/email/preview.ex
  - lib/edenflowers/email/previews.ex
  - test/edenflowers/courses/course_registration_test.exs
parent_task_id: TASK-133
type: feature
ordinal: 258000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie accepts real bookings through Instagram and other channels. They must reserve places when she accepts them, not wait for a customer to pay an Invite link. Confirmation and payment are separate facts, just as a placed Custom Order can still be unpaid. Ordinary public course links suffice for customers who should book themselves.

The user explicitly confirmed: manual bookings immediately have status confirmed, count their places and appear in normal bookings even unpaid; default is pay at course; Jennie may add after online cutoff or at/over full capacity; she can mark real money already received using its actual method; optionally send booking confirmation; send ordinary day-before reminders to these bookings; payment links remain an explicit collection option, not automatically opened/emailed on entry.

Change the resource-owned :add_manually action to create the confirmed commitment and confirmed_at, with snapshotted price/tax and either a positive Balance or an actual initial Payment through shared actions. Do not add a paid boolean or resurrect awaiting_payment. Remove CourseRegistration's explicit :record_payment prohibition; expose/reuse Payable.record_payment, ordinary amount/method validation, existing settlement components, undo/refund behaviour and existing payment-method vocabulary. Stripe money still comes from Stripe, never a manually invented Stripe Payment. Keep field/group-size validation. Manual capacity/cutoff exceptions are admin-only; website checks remain.

Keep website :register pending, same-ID :revise and payment confirmation, no temporary holds, no places for unpaid website rows, and hidden incomplete checkouts. Retain those rows; remove :discard/discard_registration, discard_abandoned and obsolete normal hard-deletion/policy/caller paths. Do not remove payment reconciliation, reminder or email jobs. Jennie's accepted manual booking is cancelled through existing booking cancellation, not withdrawn/deleted. Never-paid cancellation frees places without inventing a refund; existing terms/kept choices otherwise stay.

Remove the Invite list/create/resend/withdrawal workflow and its claim that paying first books an admin entry. Keep shared Payment Links for confirmed bookings with a Balance: paying reduces Balance, not places/confirmation a second time. Reuse existing collection/reminder email where it expresses the news accurately; remove only Invite-specific templates/scenarios/actions with no remaining legitimate use.

Emails are part of this implementation, not cosmetic follow-up. Optional confirmation must accurately describe an unpaid accepted booking and pay-at-course Balance, attach no receipt for money not received, and not stamp receipt_emailed_at when no receipt went. Paid confirmations/actual Payment-received emails must agree with real ledger state and sender stamps. Update drawer pre-save preview, actual builder/sender, PDF attachment decisions, scenarios and translations together. Day-before reminder includes unpaid confirmed manual bookings without implying payment has happened. No automatic payment-link email. Review mix print_emails sv fi en and follow ADR-0005/0006 optional-message/queue conventions.

Before rollout inspect any real pending Invites left by the old workflow. Do not automatically confirm/hold places for them or delete/abandon their existing intent/link. If they exist, explicit human classification and a narrow transition is required; no production operation is authorized here. Document neutralizing old queued/scheduled discard jobs so they cannot continue destructive cleanup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manual entry creates a confirmed booking immediately, sets its commitment time, counts places and appears in normal booking/customer views while an unpaid positive Balance remains accurately visible.
- [ ] #2 Default manual entry records no Payment and opens/emails no Payment Link; marking actual money already received records real amount/method through the shared ledger, not a separate paid flag.
- [ ] #3 Jennie can record later non-Stripe course payments using existing shared amount/method/undo/refund controls; explicit online Balance collection remains available without rebooking or duplicate confirmation.
- [ ] #4 Admin manual booking can pass online cutoff/capacity while retaining field/group-size validation and honest counts; ordinary website restrictions, unpaid-no-places and same-registration edit/retry stay unchanged.
- [ ] #5 Invite product UI/creation/resend/withdrawal semantics and normal registration hard-delete/purge jobs are removed; retained pending website rows stay hidden from bookings and all payment/email/reminder jobs still work.
- [ ] #6 Optional confirmation and real pre-save preview agree for paid/unpaid manual bookings: unpaid confirmation has no receipt or receipt stamp; actual payment uses correct receipt behaviour. Ordinary day-before reminders include unpaid confirmed manual bookings.
- [ ] #7 Tests cover never-paid manual cancellation, initial paid/unpaid creation, after-cutoff/full manual exceptions versus website checks, subsequent offline/link payment, no double place consumption and late money after cancellation.
- [ ] #8 All changed templates/translations have Email.Previews scenarios and mix print_emails sv fi en review; legacy pending-Invite classification and obsolete queued-discard-job rollout handling are documented without mutating production.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
First test the three commitment points: pending website checkout, confirmed unpaid manual entry and confirmed entry with real initial Payment. Change :add_manually/initial states and shared record_payment exposure, not the website flow or payment engine. Reuse generic settlement UI/domain interfaces for actual methods and Balances. Add admin-only cutoff/capacity bypass, leaving website pricing/preparation strict. Remove Invite UI and hard-delete/purge entry points after callers move to confirmed bookings/cancellation. Update confirmation sender/preview/PDF/stamps and reminder cases together; render all languages. Test actual later offline/link collection, cancellation and place counts. Document safe treatment of any legacy Invites and queued old purge jobs; do not blindly revert the old October 23/25 commits.
<!-- SECTION:PLAN:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 04:45

---

Supersedes this subtask's earlier retained-Invite withdrawal plan. User confirmed immediate accepted manual bookings, pay-at-course default, manual authority past cutoff/over capacity, explicit rather than automatic links, and optional truthful confirmation plus normal reminders. No Invite workflow is to be implemented.

---

author: @claude
created: 2026-10-26 04:46

---

Supersedes the prior retained-Invite/withdrawal design. User confirmed removing Invites, confirming Jennie-entered unpaid bookings immediately with places, allowing manual cutoff/capacity exceptions, default pay-at-course, optional explicit link collection, optional booking confirmation without unpaid receipt, and ordinary day-before reminders.

---
<!-- COMMENTS:END -->
