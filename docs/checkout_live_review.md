# `CheckoutLive` review punch list

Reference document for the post-refactor review of
`lib/edenflowers_web/live/checkout_live.ex` (863 lines after the
`refactor/checkout-simplification` branch).

Strike items as they land. Each item carries the original rationale
so the *why* survives even if the *how* changes during implementation.

---

## Priority 1 — quick structural wins

### 1. Consolidate function components into one block ✓

Done. `field_errors/1` + `field_error_messages/1` + `form_button/1`
moved to sit alongside `gift_card_slot/1` / `card_drawer/1` right
after `render/1`. Mid-file `# Components` banner removed.

Order in the block: utility components first (`field_errors`,
`form_button` — used everywhere), then page-specific components
(`gift_card_slot`, `card_drawer`).

---

### 2. Rename `save_form_4` → `pay` ✓

Done. Template `phx-submit` and both `handle_event` clauses renamed.
The "Step 4 does not save form data" comment that was justifying the
old name was also removed — `pay` makes the meaning self-evident.

---

### 3. Derive DOM section IDs from a single helper ✓

Done. New `section_id/2` helper is the single source of truth:

- Four template `id={section_id(@id, :contact_details)}` etc. replace
  the magic `-section-N` literals
- `next_section_id/2` delegates (with its existing two-clause shape
  to keep the `nil` fallback)
- `scroll_to_state/2` calls `section_id/2` instead of inlining

If `@checkout_states` ever reorders, only `state_index/1` notices —
all six call sites adjust automatically.

---

### 4. `recipient_label/2` should take an atom, not a string ✓

Done. Inner `case` clauses now match `:address` / `:phone`; the two
template call sites pass atoms. Typos pattern-match-fail with a
clear `CaseClauseError` instead of falling silently through.

---

## Priority 2 — judgment-call improvements

### 5. Flatten `setup_stripe/2` by extracting `persist_payment_intent/3` ✓

Done. `setup_stripe/2`'s create-path is now a flat three-line case
that delegates the persist branch to `persist_payment_intent/3`.

The "create failed" branch stayed inline (two lines: Logger.error +
stripe_unavailable). Extracting it would have named the lines but
cost one more hop — judgment call resolved in favor of less
abstraction.

---

### 6. Sub-section the `# Utilities` block ✓

Done. The catch-all `# Utilities` block is now five labelled
sub-sections:

- `# General` — `handle_mount_error`, `recipient_label`, `actor`
- `# Forms` — `make_form`, `build_submit_form`, `assign_forms`,
  `submit_form`, `forward_delivery_address_error`
- `# Order` — `reload_order`, `ensure_fulfillment_default`,
  `cart_has_items?`
- `# DOM helpers` — `section_id`, `next_section_id`, `scroll_to_state`
- `# Stripe` — `maybe_setup_stripe`, `ensure_stripe_for_state`,
  `setup_stripe`, `persist_payment_intent`, `sync_payment_intent`,
  `stripe_unavailable`

`size_label/1` moved up to sit next to `card_drawer/1` (its only
caller), removing the cross-file distance between component and its
helper. This also resolves the latent-risks note at the bottom of
this doc.

---

### 7. Tag `cart_has_items?/1`'s success case

Lines 780–781 return `:ok` on success and `{:error, :empty_cart}` on
failure. The `with` at line 31 then matches against
`{:ok, fulfillment_options}` from a different clause. Mixing
untagged success (`:ok`) with tagged tuples (`{:ok, _}`) in the same
`with` makes the `else` block ambiguous about which clause failed.

- [ ] Change `cart_has_items?/1` success to `{:ok, :has_items}`
      (or similar)
- [ ] Update the `with` clause at line 31 to match

---

### 8. Add a comment explaining the steps/inner_block split

The outer step rendering (titles, summaries, edit links, position
numbers) lives in `EdenflowersWeb.CheckoutComponents`. The step
contents (forms, fields) live in `render/1` here, passed as
`inner_block`. That split is unavoidable but non-obvious to a cold
reader.

- [ ] Add a one-line `<%# ... %>` comment above the `<.steps>` call
      at line 75

---

### 9. Hardcoded date at line 222 → deferred to feature work

```elixir
:if={day == ~D[2025-05-07]}
```

This is a placeholder for a **key-dates feature**: the shop wants to
highlight notable dates (Mother's Day, Valentine's Day, etc.) in the
calendar, sourced from the database.

Tracked in **[#208](https://github.com/davemccrea/edenflowers_store/issues/208)**.
No action on this branch; the placeholder stays until the feature
lands.

---

## Priority 3 — larger investment

### 10. Reduce state-machine duplication across modules ✓

Resolved. `Order` now exposes `checkout_states/0`; the LV and
`CheckoutComponents` both read `@checkout_states Order.checkout_states()`
at compile time. Adding a state means one edit on `Order`; the
attribute caches propagate via compile-time inlining.

The state→action mappings (`submit_action_for/1` in LV, the three
`edit_step` handler clauses) stay in the LV — they're UI concerns,
not domain concerns, and centralizing them would have meant a new
module just to hold ~10 lines.

---

## Already addressed (no action needed)

The review noted these as strengths:

- File is sectioned by lifecycle (`# Markup`, `# Event Handlers`,
  `# Info Events`, etc.) — section banners do real work
- Comments are load-bearing; none restate code
- State atoms drive everything; no magic numbers
- Event handler clauses read like a checklist of legal transitions
- Stripe boundary is well-isolated via `stripe_api()` config

The review also flagged but declined:

- **Validate-form guard for nil form**: technically possible, but the
  invariant is enforced by which step renders which `phx-change`.
  Adding a guard would self-document but isn't load-bearing.
- **Form `<.form>` deduplication**: three near-identical `<.form>`
  definitions across step 1/2/3, but each contains different inner
  content. Dedupe would save ~12 lines and hurt clarity.

---

## Latent risks / unscored observations

- ~~**`size_label/1`** is only used by `card_drawer/1`.~~ Resolved in
  item 6 — `size_label/1` now sits right next to `card_drawer/1`.
- **`<.card_drawer>` at line 332** sits inside `<Layouts.app>` but
  outside `<.container>`. Probably intentional (drawer escapes
  container's max-width) but worth confirming visually once.
