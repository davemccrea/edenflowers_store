---
id: TASK-133
title: >-
  Retain purchases and restore confirmed manual course bookings payable at the
  course
status: ready-for-agent
assignee: []
created_date: '2026-10-25 22:22'
updated_date: '2026-10-26 04:46'
labels:
  - spec
  - customers
  - admin
  - developers
dependencies: []
references:
  - lib/edenflowers/payments.ex
  - lib/edenflowers/payments/payment.ex
  - lib/edenflowers/payments/changes/cancel_open_payment_intent.ex
  - lib/edenflowers/orders/order/admin.ex
  - lib/edenflowers/orders/order/payment_link.ex
  - lib/edenflowers/courses/course_registration/admin.ex
  - lib/edenflowers/courses/course_registration/payment.ex
  - docs/adr/0002-payments-are-records.md
  - docs/adr/0004-orders-are-the-sales-record.md
priority: high
type: refactor
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retain the records Stripe payments belong to, remove destructive purchase cleanup, and let Jennie enter a real Course booking with payment due at the course using the same ledger as Custom Orders.

**Why:** Removing hard deletion is simpler and safer than racing Stripe cancellation against a disappearing order or registration. Jennie also needs to accept bookings received through Instagram or another channel without making the customer pay a special Invite link first. A booking she accepts is a commitment to provide places, just as a Custom Order is a commitment to make flowers; whether money has arrived is a separate fact. The goal is less business machinery, not another payment framework.

## Final agreed decisions (supersede the original issue)

The user confirmed this revised model through interactive grilling in this session. Earlier versions of TASK-133 proposed a retained Invite-withdrawal workflow and explicit Custom Order archiving. Those proposals are superseded: **implement neither an Invite workflow nor an Archive action/marker/view**.

1. Ordinary course-page links suffice when Jennie wants someone to book online. Remove creating, resending and withdrawing special unpaid Invites.
2. Jennie can add a booking received through Instagram or another channel. It is confirmed immediately, holds its places immediately and appears in normal bookings, even when still unpaid.
3. Manual entry defaults to pay at the course. Jennie can instead mark an actual payment as already received, selecting its real method and recording a Payment row through the shared payment actions. Do not add a paid boolean independent of the ledger. Later collection, partial payments, undo and refunds reuse existing shared behaviour rather than course-only implementations.
4. Jennie may add a manual booking after online booking closes or when the course is full. Show actual booked places honestly, including overcapacity; do not introduce capacity locking/reservation machinery for this admin decision. Keep ordinary field validation and the current per-booking group-size limit unless separately agreed.
5. A manual booking offers an optional confirmation email and Jennie's message. Confirmation means the places are booked, not necessarily paid. An unpaid confirmation carries no receipt and must not stamp a receipt as sent. These confirmed manual bookings receive the ordinary day-before reminder even while unpaid. A receipt requires actual recorded money.
6. No payment link is automatically opened/emailed by adding an unpaid manual booking. Payment links and payment reminders remain explicit collection options for an already accepted booking's Balance; removing Invites does not mean removing shared Payment Links. New ordinary website purchases still use the normal public course checkout.
7. Website course checkout stays pending and holds no places until payment confirms it. Keep same-registration editing/retry, received-money recording and mismatch handling. Retain unfinished checkouts but keep them out of normal admin/customer booking lists. No routine Oban job deletes registrations.
8. Remove Custom Order hard deletion; use the existing cancellation/settlement actions and Cinder table filtering. OrdersLive already defaults to Still to do; cancelled orders remain accessible through All orders, search and direct detail links. There is no separate archive state, eligibility, timestamp, action, log event or Archived view to build. Settlement warnings must remain visible independently of the working-list filter.
9. No normal application action physically deletes a placed order or course registration. Keep the existing cleanup for old empty store carts without lines or a PaymentIntent. Protect recorded Payment history with restrictive parent foreign keys instead of cascade deletion.
10. Keep recording and reconciling real money after cancellation without reopening orders/bookings or reactivating subscriptions. Refunds/amount differences remain Jennie's existing Balance-settlement workflow; no new automatic late-payment or mismatch refunds.

## Common money handling, different commitment points

| Purchase | Before payment | What payment does |
| --- | --- | --- |
| Website store checkout | Saved cart; not an admin placed order | Records actual money and places the saved order |
| Custom Order Jennie enters | Already placed and visible; may owe money | Records money and reduces its Balance |
| Website course checkout | Pending registration; hidden from normal bookings; holds no places | Records actual money and confirms the saved registration |
| Course booking Jennie enters | Already confirmed and visible; holds places; may owe money | Records money and reduces its Balance; does not book places or send confirmation a second time |

For all four, actual Payments/refunds are the financial truth, duplicate Stripe events cannot duplicate money, and a price/payment difference becomes a Balance to collect or refund. Keep payment status separate from fulfillment/booking commitment. This does not claim Stripe and PostgreSQL share one atomic transaction or that every callback arrives immediately.

## History: why the code changed, and what to keep

The user recalled that manual course bookings could previously be paid at the course. Git confirms two separate business changes:

- **715949c8, 23 October 2026:** 'Take course payment only by payment link' removed recording payments taken at the course; manual bookings held places awaiting payment through a link.
- **2cacf372 / TASK-120, 25 October 2026:** 'Book a course place only once it is paid' changed manual bookings into pending Invites that held no places. TASK-120's stated motivation was: 'Unpaid bookings holding places make the seat counts, the emails and their copy branch on booked but not paid. Paid-only booking leaves one meaning of booked.' Confirmation always carrying a receipt and reminders going only to paid bookings were deliberate simplifications under that rule.

Those were product decisions, not technical necessities. This issue intentionally replaces paid-only manual booking and payment-link-only collection. Domain semantics must fit how Jennie takes bookings; do not reject unpaid accepted bookings just to simplify email copy. Do not blindly revert the commits: they also changed checkout holds, payment completion, emails and tests. Keep the later TASK-123 in-place checkout and accepted mismatch behaviour.

Keep the current pending/confirmed/cancelled model where possible: pending means website checkout not yet committed; confirmed means places Jennie/the successful checkout committed to provide; cancelled means called off, regardless of whether payment ever arrived. An unpaid confirmed manual booking has a positive Balance. Cancellation uses the existing terms/default-refund and explicit refund/kept choices without inventing a new policy for collecting cancellation fees from a never-paid customer.

TASK-42's Custom Order deletion is superseded by cancellation plus filtering. TASK-120's Invite/pending deletion/payout-only assumptions are superseded, but its no-temporary-website-holds simplification remains. TASK-122's discard-or-retain checkout wrapper stays superseded; do not restore it. TASK-123's same-ID revisions, mismatch acceptance and no customer self-edit/cancel for confirmed bookings remain. Ordinary group bookings, existing cancellation terms and refund limits are not removed by this issue.

## Current implementation facts and concrete risk

- Payments.complete/1, Payments.prepare/2, RecordPayment, ReportAmountMismatch and Payable already provide shared actual-amount recording, Balance handling, duplication protection, reconciliation and refunds. A normal booking's existing :record_link_payment path can collect a confirmed manual booking's Balance instead of treating it as a new booking.
- CourseRegistration currently explicitly rejects :record_payment in its validations block. Remove that course-only restriction and expose/reuse the shared action and existing payment-method UI rather than reintroducing legacy mark_paid bookkeeping.
- :add_manually currently creates pending rows, opens a link and queues the Invite email. Change it to a real confirmed booking action, with confirmed_at set when accepted and optional actual initial Payment. Ordinary website :register stays pending. Do not add duplicate paid/payment-status attributes.
- PriceBooking currently allows an after-cutoff option but still rejects seats greater than seats_left. Apply the user's admin-only cutoff/capacity exception without weakening website preparation or field validation. Places are counted from confirmed bookings, including unpaid manual bookings; unpaid website rows still count for nothing.
- SendConfirmationEmail currently always generates/attaches a receipt and stamps confirmation_emailed_at and receipt_emailed_at together. Revise the real sender, previews and templates consistently for unpaid confirmed bookings; changing copy alone is insufficient. The booking drawer currently previews/emails a payment link and must instead preview the actual booking confirmation.
- Custom Order :delete_custom and course :discard physically delete; discard_abandoned runs nightly for old pending website registrations. Payment foreign keys currently cascade deletion of their order/registration into ledger rows. The course-to-registration foreign key already blocks deleting a course that has registrations.
- Commit c61ecbe4 removed stronger destructive-operation guards and tests. At reviewed HEAD 62a301bd, 1,622 existing tests passed, while three temporary deterministic tests with real Ash/database actions and mocked Stripe reproduced stale-intent registration deletion, intent attachment during deletion, and deletion of both an order and its new Payment during replacement-intent cancellation. This is historical review evidence, not a new implementation test result or a claim about production frequency. Source scenarios remain in git show c61ecbe4^:test/edenflowers/courses/discard_registration_test.exs and git show c61ecbe4^:test/edenflowers/orders/custom_order_test.exs. Adapt their preservation guarantees to the new retained model instead of restoring obsolete deletion orchestration.

## Payment, settlement and late-event invariants

1. Every verified successful Stripe payment belonging to a retained purchase is recorded once using actual amount_received. Keep event provenance/parent checks, unique payment/refund IDs, exactly-one-parent constraint, actor permissions and transactional consistency. Normal callbacks for a confirmed manual booking record money without confirming/consuming places again.
2. A late payment on a cancelled order or booking is still recorded, leaves it cancelled/unbooked and exposes the money to refund through existing settlement/attention views. It must not reopen fulfillment, restore course places, restart a cancelled subscription, send a normal booking confirmation or schedule a booking reminder. Do not automatically refund it merely because it arrived late.
3. Existing Cinder filters are presentation only. Payment/refund parent relationships, system reads, customer history, receipts, VAT snapshots, monthly accounting and revenue remain accessible. All orders/search/direct links can still find cancelled Custom Orders. No global AshArchival/base filter or silent loss of financial attention.
4. Reuse existing cancellation and settlement. A never-paid confirmed manual booking can be cancelled, frees its places and records no fictitious refund. A paid/part-paid booking follows the existing financial calculations and actual transactions. Recording an offline payment closes/updates stale online collection through the existing shared cancellation/Balance machinery, but a late Stripe success must still be accounted for if it arrives.
5. Zero Balance/settled? means nothing is owed according to recorded transactions now. It is not proof that no Stripe payment is processing or that no webhook was missed. Do not add an API or hide operation that promises permanent finality.
6. Closed/cancelled records refuse new payment preparation, but an existing client secret can still yield a delayed success. Keep nonterminal PaymentIntent references recoverable when cancellation fails or reports processing. An old cancellation must not clear a newly attached intent. Never hold a database transaction over a Stripe network call.
7. Keep reconciliation jobs, email jobs and reminders. Order and course reconciliation currently run every ten minutes, checking attached intents older than five minutes and newer than seven days; cancelled parents are currently excluded. Extend eligibility where needed for outstanding payments on retained cancelled records and prove it via the scheduler/worker, not only a direct Payments.complete call. Keep cadence and explicitly document age-window/manual recovery limits; no Stripe-wide polling or promise of indefinite automatic recovery. Existing refund ingestion/sync remains; no new scheduled refund scanner.
8. Restrictive Payment foreign keys protect already-recorded money even if application authorization is bypassed. Removing destructive application operations separately protects in-flight/unrecorded money. Neither substitutes for the other. Keep two real parent foreign keys and existing reversal behaviour; no new parent table or trigger framework.

## Required race/outcome tests

| Situation | Required result |
| --- | --- |
| Revise pending website registration, then payment succeeds | Confirm saved details/places, record actual amount once, expose any difference as Balance |
| Payment confirms before stale website edit | Refuse edit; keep confirmed details and money |
| Jennie adds an unpaid manual booking | Confirm once, count places immediately, show Balance and pay-at-course information; no fake Payment/receipt/automatic link |
| Jennie adds a booking marked paid | Record real method/amount in the ledger, count places once, show correct Balance/receipt; no paid flag disconnected from money |
| Manual booking added past cutoff/at full capacity | Accept admin commitment and display actual counts; website booking restrictions remain unchanged |
| Payment link settles an existing manual booking | Record money and applicable receipt; do not consume places or send original booking confirmation again |
| Manual booking is cancelled before payment arrives | Remain cancelled; record any later money once; show refund obligation; no new places/booking confirmation |
| Offline collection and previously started Stripe payment both arrive | Retain both actual transactions; expose any excess to refund, never silently discard money |
| Cancelled Custom Order receives late success/refund | Keep parent/ledger history and cancellation; show new financial obligation despite working-list filter |
| Webhook and reconciliation complete the same payment | One ledger entry and the applicable notification once |
| Raw parent delete after paid/refunded/reversed history | Database rejects deletion; preserve parent and Payments |
| Unpaid manual confirmation/reminder | Accurate booked-but-not-paid copy, optional confirmation, ordinary day-before reminder, no receipt for money never received |

## Scope: deliberately smaller, not a historical revert

No Invite creation/list/resend/withdrawal product workflow; no Archive action/timestamp/flag/view; no extra hidden/deleted marker; no paid boolean; no legacy awaiting_payment booking state; no temporary website seat holds; no routine registration deletion; no new payment framework, polymorphic parent table, general locking layer, automatic mismatch refunds, blanket checkout rewrite or unrelated architecture work. Prefer existing conditional writes and database uniqueness; add a narrowly justified lock only if a reproduced invariant requires one. Do not suppress useful booking/payment behaviour merely to eliminate an honest email wording variation.

Keep current name/email/locale and per-booking size validation; this issue does not add phone-only registrations, new discounts, arbitrary manual pricing, new payment methods or permission changes. Keep existing group-seat removal and cancellation/refund policy, except removing the assumption that a confirmed booking is necessarily paid. Keep customer self-edit/self-cancel unavailable for confirmed course bookings.

Operational retention is not a legal promise to keep personal data forever. TASK-116 still owns privacy/retention policy; its proposed seven-year period is not approved here. Future lawful anonymisation/retention work must preserve required financial references and resolve outstanding Stripe operations. Do not implement a new retention period now.

## Legacy data, documentation and rollout

- Inspect existing pending Invites (pending registrations with payment-link tokens) before rollout. They were invitations, not necessarily accepted bookings: do not automatically confirm them/consume places, delete them, or abandon already-issued links/intents. If any exist, require explicit human classification and a narrow transition of those records before retiring the Invite-only assumptions. Existing confirmed/cancelled bookings and all Payments remain untouched. No production inspection or mutation is authorized by issue creation.
- Existing confirmed booking payment links must continue to collect Balances. Remove only Invite-specific semantics/templates/scenarios that truly have no confirmed-booking use; reword retained collection email/payment pages so they ask for payment of an already booked place, not promise that paying first creates it.
- Neutralize previously queued/scheduled registration-discard jobs safely during deployment. Remove only their obsolete trigger/action/worker paths, not payment reconciliation or email/reminder queues. Do not let an old worker continue deleting records after the retention change.
- Generate restrictive foreign-key migrations/Ash snapshots from resource declarations. No archive migration. Do not delete/backfill away pending checkouts or fabricate recovery for records already lost historically.
- Amend CONTEXT.md and ADR-0002/0004 to record confirmed-versus-paid semantics, manual pay-at-course collection, no Invites, cancellation plus filtering and retained late money. Update resource descriptions, task references and email/job documentation consistently. Historical TASK-42/120/122 decisions remain historical; this issue explicitly supersedes the affected behaviours.
- Every changed email/translation must have realistic paid/unpaid/manual/online scenarios in Email.Previews and be reviewed with mix print_emails sv fi en. Confirmation/PDF attachment decisions, sender stamps, drawer previews and actual delivery must agree. Preserve existing optional-message and queue/retry conventions; do not send a receipt for unreceived money.
- Before any later production deployment or direct database operation, follow CLAUDE.md: backup, confirm dump in tmp/, then the normal release workflow. Document migration/legacy-Invite/obsolete-job/rollback compatibility. Issue editing authorizes no application implementation or production operation.

## Industry context and limits

The useful established pattern is separating commitment, payment status and list visibility, not claiming every platform retains every abandoned checkout forever. Shopify distinguishes cancellation from archiving/closed views; here existing Cinder filtering is sufficient, so do not copy the archive feature. Stripe recommends reusing/updating the PaymentIntent for resumed checkout and processing completion through server webhooks. Reuse the installed integration; this does not require changing Stripe APIs. The no-routine-registration-deletion choice is a small-store simplicity trade-off: retained rows accumulate while in-flight money keeps a stable parent.

Sources verified during this discussion:
- https://help.shopify.com/en/manual/fulfillment/managing-orders/canceling-orders
- https://help.shopify.com/en/manual/checkout-settings/order-processing
- https://docs.stripe.com/payments/payment-intents
- https://docs.stripe.com/payments/payment-intents/verifying-status
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No normal app action or routine Oban job deletes course registrations or placed orders. Pending website registrations stay retained, hidden from normal bookings and uncommitted until payment; existing empty unused store-cart cleanup remains.
- [ ] #2 The Invite workflow is removed. Jennie adds confirmed manual bookings that immediately count places and appear in normal booking lists, may bypass online cutoff/capacity, and default to payment at the course.
- [ ] #3 Manual entry can record an actual already-received payment with its method; later offline collection, undo, partial settlement/refunds and optional online Balance collection reuse shared payment actions. No fake paid flag or automatically emailed/opened link.
- [ ] #4 Optional manual booking confirmation and ordinary day-before reminders work while unpaid, with accurate pay-at-course wording and no unpaid receipt; actual paid receipt handling, previews, stamps and all email languages agree.
- [ ] #5 Custom Order Delete is removed; existing cancellation/settlement plus Cinder Still to do/All orders filtering suffice. No archive action/schema/view is added; cancelled orders stay searchable and directly accessible, including financial attention.
- [ ] #6 Both Payment parent foreign keys reject parent deletion instead of deleting ledger rows. Courses with registrations remain deletion-restricted; actual paid/refunded/reversed history is preserved even outside normal Ash authorization.
- [ ] #7 Existing shared actual-amount recording, duplicate protection, mismatch Balance handling, refunds and reconciliation work for confirmed manual bookings and retained cancelled records. Late money does not reopen/rebook/reactivate a cancelled purchase.
- [ ] #8 Targeted tests cover the full outcome matrix, closed-link preparation, both relevant edit/payment orderings, offline-versus-Stripe double collection, manual capacity exceptions, real database deletion protection and scheduler recovery; mix precommit passes.
- [ ] #9 CONTEXT/ADR/email/job documentation and rollout instructions match the revised model, including explicit legacy-Invite review, obsolete purge-job handling, point-in-time settlement/reconciliation limits and separate privacy retention. No production operation or historical-data destruction is performed.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. **Protect the ledger first — TASK-133.1.** Change only the two Payment-parent cascade behaviours, generate the migration/snapshots and assert real database deletes cannot erase paid/refunded/reversed history. Keep the course-parent restriction and existing two-FK/Stripe-ID/reversal invariants.

2. **Keep shared money handling valid after cancellation — TASK-133.2.** Add narrow regression tests for late success/refunds/duplicate events on cancelled orders/registrations, plus normal pending checkout and existing confirmed-booking Balance payments. Separate recording money from placing/confirming/reactivating; preserve outstanding intent IDs across unsuccessful cancellation and extend existing reconciliation selection appropriately. Keep cadence/window limits explicit. No blanket locking layer or Stripe network calls inside transactions.

3. **Replace Invites with real manual bookings — TASK-133.3.** Keep website :register/:revise semantics and no temporary holds. Make :add_manually create a confirmed commitment immediately, including confirmed_at, counts and positive Balance while unpaid. Default to pay at course; allow actual initial payment with a selected method through the shared ledger. Remove the course-only :record_payment prohibition and reuse shared settlement UI/actions. Permit admin cutoff/capacity exceptions without weakening website checks. Remove Invite list/create/resend/withdrawal semantics and registration hard deletion/purge jobs. Keep explicit payment-link/reminder collection for confirmed Balances. Update real confirmation sender/preview/PDF/stamps and reminder eligibility for unpaid confirmed bookings, with all language scenarios. Plan human review of any legacy pending Invites and safe retirement of queued purge jobs.

4. **Remove Custom Order deletion without adding a replacement state — TASK-133.4.** Remove Delete UI/domain/action/policy references and truly unused destructive-only helpers. Keep existing cancel/refund/stock/log behaviour. Verify the current Cinder Still to do default, All orders, search, direct details, Overview settlement and accounting rather than adding archive markers or filters. Existing empty-store-cart purge remains.

5. **Close integrated tests, documentation and rollout — TASK-133.5.** Verify the parent matrix at real resource/worker/UI seams; each earlier subtask carries its own regression tests. Run mix precommit, payment/refund/booking/order/accounting tests and all email render previews. Amend CONTEXT/ADR-0002/0004 and email/job docs. Explicitly supersede the paid-only/manual-link-only domain statements from TASK-120/715949c8 without reverting unrelated work. Document legacy-Invite review, queued-discard-job retirement, restricted-FK migration and rollback limits. Production deployment remains separately approved and backup-first.

## Implementation discipline
- Reuse the same Payment ledger and calculations for all four purchase types; only commitment points differ.
- No archive migration/action/view, Invite-withdrawal replacement state, paid boolean, new payment engine or restored seat-hold scheduler.
- Manual creation marked paid must record actual money/method and never display success without its ledger entry; avoid duplicate confirmation/place counting when later payments arrive.
- Test a never-paid confirmed manual booking's cancellation: free places, no fictitious refund, existing terms/kept choices unchanged.
- Test a confirmed manual booking being paid through a link as a Balance payment, not a fresh booking.
- Test late money on a cancelled Custom Order remains visible in Overview even though the default working table excludes that order.
- Do not automatically convert legacy pending Invites into confirmed bookings; real data requires explicit review before retiring old assumptions.
<!-- SECTION:PLAN:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 22:24

---

Scope confirmed through the grilling skill and interactive prompts in this session: cancelled-and-settled Custom Orders; separate Archive action; Archived filter plus direct detail access; retain course registrations and withdraw Invites; restrictive Payment parent FKs; reuse shared payments and manual Balance settlement. Follow-up clarification: zero Balance is point-in-time, not proof of no future Stripe event; late obligations must remain visible even when archived. No implementation or production operation authorized. Related historical tasks remain historical; this issue replaces their destructive behaviour rather than reopening all prior architecture work.

---

author: @claude
created: 2026-10-26 04:45

---

Latest scope supersedes the initial Archive/Invite-withdrawal proposal and its earlier comment. Confirmed through interactive prompts: no Archive feature; use existing Cinder filtering; no Invite workflow; Jennie's manual bookings are confirmed immediately and count places, may exceed online cutoff/capacity, default to pay at course and optionally record actual paid money with its method. Confirmation can be emailed before payment without an unpaid receipt; normal reminders include these bookings. Explicit payment-link collection remains. Keep retained website checkouts, shared payment safety and restrictive ledger-parent FKs. Documentation/issues only; no application implementation authorized. Historical reasons verified in TASK-120 and commits 715949c8 / 2cacf372.

---

author: @claude
created: 2026-10-26 04:46

---

REVISED SCOPE CONFIRMED by the user through interactive grilling: remove the Invite workflow and the entire Archive proposal. Jennie-entered Course bookings are confirmed immediately, hold places even unpaid, can bypass online cutoff/capacity, default to pay at course, and optionally record real money/method or send booking confirmation without an unpaid receipt. Day-before reminders include these bookings. Payment links remain explicit Balance collection only. Custom Orders use existing cancellation plus Cinder filtering; no archive marker/action/view. Keep purchase retention, restrictive Payment-parent foreign keys, shared money handling and late-payment/reconciliation safety. Earlier comments describing Archive/Invite withdrawal are historical and superseded. Application implementation and production operations remain unauthorized in this documentation-only session.

---
<!-- COMMENTS:END -->
