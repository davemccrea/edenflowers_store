# Test strategy audit and first pruning batch — 28 October 2026

## Verdict and architecture

The proposed 50% reduction is unsupported. This first batch removes 65 Elixir
scenarios, consolidates three further cases, and removes one JavaScript
presentation test. It does not establish an irreducible minimum.

[Testing policy](../agents/testing.md) remains the architecture:

- Public Ash actions against sandboxed Postgres own financial correctness,
  authorisation, persistence, transitions and queued effects.
- Pure tests own substantive rounding, allocation, calendar and scheduling logic.
- UI tests own submission wiring, stale-page behaviour, errors, previews and
  distinct customer-visible states, not repeated domain matrices.
- Integration tests own signed raw-body webhooks, retry responses, adapter
  contracts, document rendering and HTTP access boundaries.
- Semantic localisation and legal/editorial review remain separate from
  catalogue validation. Follow the [translation policy](../../priv/gettext/README.md)
  and its outstanding review queue.

Requirements come from `CONTEXT.md` and ADRs 0001–0006, particularly commitment
versus payment, the shared ledger, retained purchases and once-queued emails.
Neither similar test names nor a passing replacement suite establish equivalence.

## Executable inventory

The initial assessment enumerated ExUnit's registered tests: 155 files and 1,757
cases from 1,572 test declarations. Generated expansion contributes 185 cases.
There were 1,500 cases in async modules and 257 in synchronous modules.

| Changed group | Before | After |
| --- | ---: | ---: |
| `payments/payable_test.exs` | 126 | 108 |
| `payments/payment_retention_test.exs` | 7 | 3 |
| `pricing/promotion_test.exs` | 15 | 13 |
| `checkout/payment_link_states_test.exs` | 86 | 53 |
| `checkout/pay_live_test.exs` | 19 | 14 |
| `courses/course_pay_live_test.exs` | 13 | 10 |
| `gettext_test.exs` | 6 | 5 |
| `design_rules_test.exs` | 2 | 0 |
| **Full Elixir suite** | **1,757** | **1,689** |
| **JavaScript suite** | **40** | **39** |

Paths in this table are relative to their existing `test/edenflowers/` or
`test/edenflowers_web/features/` locations, except the two web-level check files.

## Removal and consolidation ledger

### Shared ledger: 18 removals

`payable_test.exs` now has a `shared ledger` describe block against orders.
The corresponding booking copies are removed for these case suffixes:

- `paid in full by ... is settled` (all three combinations).
- `part-paid owes the rest`.
- `a part-payment leaves the rest owed`.
- `a payment larger than the balance is refused`.
- `a Stripe payment can't be recorded by hand`.
- `a negative payment is refused: money handed back is a refund`.
- `a refund keeps its reason`.
- `a refund above what was paid outside Stripe is refused outside Stripe`.
- `a refund by a method holding nothing is refused`.
- `a refund while something is to collect is refused`.
- `a refund through Stripe above what was paid through it is refused`.

The booking copies of `paying the whole balance by ... settles it` for MobilePay,
Zettle and Zervant are also removed. Cash still exercises booking recording.
These 16 cases share `Payments.Payable` and its validation implementations.
Both resources retain cancellation, settlement, goodwill, undo and integration
coverage; booking seat-dependent Total due remains independently exercised.

Both `an uncommitted one owes nothing yet` cases are removed: they asserted only
`committed?`, not money. The retained uncommitted recording/cancellation refusals
and unsettled-list cases protect the consequential obligations.

### Payment-page states: 33 removals

The two Cartesian products in `payment_link_states_test.exs` produced 60 cases;
27 representatives remain. The explicit tuples in that file are the retained
set, and all other combinations from those original products are removed.

`PayLive.render/1`, `CoursePayLive.render/1` and `PaymentLink.payment_form/1`
separate money state from method/time copy. Representatives retain their
consequential intersections: cancelled/refunded precedence, overpayment,
goodwill, fulfilled pickup/delivery, and past courses. Domain tests are not
being substituted for payment-page rendering protection.

### Duplicate payment-page tests: six removals, two consolidations

In `pay_live_test.exs`, both generated `thanks the customer for a paid, fulfilled
... order` cases, `says the order was collected once it's fulfilled`, and `says so
once the order is refunded` are covered by the retained state representatives.
Fulfilled thank-you text, hidden fulfilment copy and the order reference remain
asserted there.

In `course_pay_live_test.exs`, `says so once the booking is refunded` and
`a cancelled booking does not promise places or request payment` are covered by
the retained booking representatives. Ordinary/goodwill ledger distinctions stay
in the domain tests.

The order partial-payment test and booking nothing-paid test are consolidated
into their corresponding representatives, retaining amount and label assertions.
Actual pay submission, stale balances, prepared-record translation, token-only
access restrictions and payment-arrival interactions remain separate tests.

### Payment-parent constraints: four removals

For each parent, `with refunded history cannot be deleted directly` and
`with reversed history cannot be deleted directly` are removed. They retained
the same original Payment and tested the same unconditional restrictive foreign
key as the paid-history case. One `with payment history cannot be deleted
directly` case remains per parent, plus the separate course-parent restriction.
Application cancellation/history-preservation tests are unchanged.

### Other removals and consolidation

- Promotion lookup: remove the ordinary successful interior-date scenario;
  retain both inclusive boundaries and both outside-boundary refusals.
- Consolidate mixed-case and whitespace lookup into one input containing both.
- Remove `every audience catalogue matches its template in every language`:
  `mix gettext.check` owns broader alignment checks in CI/precommit, and
  `gettext_check_test.exs` tests malformed catalogues. Domain extraction,
  interpolation, semantic translations and linked sentences remain protected.
- Remove both `design_rules_test.exs` checks. This deliberately accepts visual
  review for the documented square-edge/hairline rules; the rules are not obsolete.
- Remove JS `shortcut hints sit outside the wrapping button row`. It froze
  ancestry and flex styling; actual shortcuts and review interactions remain.

## Validation evidence

Initial product-page failures were stale compiled SVG lookup state after new
files were added. A focused run reproduced 13 failures; forced test compilation
made the same seed pass all 23 product tests. No application source was changed.
An overlapping pair of test processes also caused a calendar deadlock; that run
is not a useful baseline or performance comparison.

The focused changed-domain/payment-page suite passes 201 cases. `mix precommit`
passes, including compile/codegen/format/Credo/catalogue checks, 39 JS tests and
1,689 Elixir cases with zero failures and one existing skip. Its normal concurrent
suite runtime was 30.5 seconds; normal runs at seeds 950916 and 785167 took 31.4
and 30.9 seconds with the same result. These are observations, not a controlled
speedup claim.

Twenty-one isolated in-memory mutations were detected by surviving tests:

- Seven UI probes: bypass cancellation/refund precedence, show pending pickup
  copy after fulfilment, promise future course places after the event, display
  pre-goodwill paid amounts on either payment page, or show closed payment forms.
- Three validation probes: accept overpayment, refund while collecting, or ignore
  method-specific refund limits.
- Two booking probes: ignore removed seats in Total due or deny confirmed commitment.
- Three shared-ledger probes: omit cash, count goodwill against amount paid, or
  allow handwritten Stripe payments.
- Two schema probes: independently drop either Payment-parent foreign key inside
  its test's sandbox transaction. The retained test observed the forbidden delete.
- Four promotion probes: exclude either date boundary, make comparison
  case-sensitive, or preserve whitespace instead of trimming it.

Two temporary-catalogue probes confirmed the existing gate rejects a missing
placeholder and a changed message key. No mutation changed application files;
no mutation framework or browser infrastructure was added. Payment browser,
wallet and 3DS smoke checks were not performed for this test-only change.

## Deferred work, not permission for further deletion

- Isolate the one constraint-altering payment-completion failure test instead of
  serialising its whole module; move already-pure groups off sandbox setup.
- Repair accumulated fixture mutations in the email-action availability matrix.
- Resolve stale booking settlement assertions about payment being unavailable
  by hand, and establish reachability of unassociated guest-registration fixtures.
- Investigate legacy pending payment links before deleting old “Invite” scenarios.
- Consider focused protection for Stripe lazy loading and the Payment exactly-one-
  parent constraint, plus one consequential real concurrency interleaving.
- Complete native/Jennie review of financial/legal wording; catalogue success does
  not close that review.
