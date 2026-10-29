# Testing

## Choose the test surface

- Test business rules through public Ash actions against real sandboxed Postgres
  (`Edenflowers.DataCase` and existing generators). Cover the domain matrix here:
  money and rounding, authorisation, state transitions, idempotency, jobs and emails.
  Mock external adapters at their interfaces, not Ash or the database.
- Don't test the framework: skip assertions that Ash persisted an attribute, a
  relationship loads, or a calculation mirrors its own expression. Test the rule
  the resource encodes.
- Use pure tests for standalone calculations with meaningful inputs and edge cases.
  Resource calculations that depend on persisted data still need the Ash interface.
- Use LiveView tests for wiring, interactions, validation errors and distinct UI
  states with meaningful live records. Assert the resulting persisted change where
  relevant; avoid repeating the entire domain matrix through each screen.
- Use Node tests for JavaScript behaviour and JS/server state contracts. No npm
  dependencies or browser framework are needed for the current suite.

## Choose assertions that survive editing

Assert observable behaviour: semantic/localised link destinations, accessible names
and ARIA state, enabled actions, money, legal commitments, and JS/state contracts.
A test should fail when the contract breaks, not when harmless presentation changes.

Avoid freezing incidental CSS, typography, layout or bullet counts, mirroring general
marketing prose, or asserting that removed historical wording stays absent. Counts,
classes and absence assertions are useful when they express actual behaviour or a
documented legal/editorial contract; explain that contract when it is not obvious.
Apply this distinction when adding coverage as well as when removing brittle
assertions.

`mix gettext.check` owns mechanical catalogue coverage, placeholders and fuzzy-flag
checks. It does not establish semantic translation correctness or Swedish human
approval. Retain linked-sentence and interpolation regression checks where they
protect meaning or link placement. Follow [translation policy](../../priv/gettext/README.md)
for editorial review and approval, especially financial/legal wording.

## Run the right gate

- `just test`: JavaScript first, then the full Elixir suite; requires Typst and local
  Postgres. `just install-typst` installs the pinned receipt renderer.
- `just test test/path_test.exs:42` or `just test --failed`: focused Elixir only;
  arguments are forwarded to `mix test`.
- `just test-js`: JavaScript only via `node --test test/js/*_test.mjs`, without Mix.
  CI pins Node 24 LTS.
- `mix precommit`: repository checks, including catalogue validation and both suites.
  CI also runs both suites and retains its existing compile/codegen/lint checks.

For runtime comparisons, measure a normal `mix test` run under comparable conditions.
`mix test --slowest N` implies trace mode and `max_cases: 1`; use it to identify slow
cases, not as the normal concurrent runtime baseline.

## Manual payment smoke check

LiveView tests and direct handler calls do not verify browser JavaScript, Stripe
wallets or 3DS. For payment-facing changes, use Stripe **test mode**:

1. Start `just dev` and `just forward-stripe`; use test keys and the listener's
   webhook signing secret in the local environment.
2. Complete a browser checkout; confirm the webhook produces the expected paid
   order/booking state and receipt/email without duplicate effects on redelivery.
3. Exercise a declined payment and a 3DS challenge (success and cancellation),
   checking the visible error/retry state and persisted payment state.
4. Check Apple Pay/Google Pay on a supported browser/device with test-mode wallet
   setup when available. Record any unavailable wallet/device check as unverified.

Keep this a small manual checklist; it is not a browser-test rollout.
