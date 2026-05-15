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

### 4. `recipient_label/2` should take an atom, not a string

Lines 668–682 dispatch on `"address"` vs `"phone"` — magic strings
that appear nowhere else. Atoms are self-documenting and typos
pattern-match-fail loudly.

- [ ] Change function head to `recipient_label(order, :address)` /
      `recipient_label(order, :phone)`
- [ ] Update three call sites (lines 177, 189)

---

## Priority 2 — judgment-call improvements

### 5. Flatten `setup_stripe/2` by extracting `persist_payment_intent/3`

Lines 807–830. The two-level `case` correctly distinguishes "create
failed (no cleanup)" from "create OK, persist failed (orphan
cleanup)". `with` would erase that distinction. Extracting the
inner branch flattens the top-level to three lines.

```elixir
defp setup_stripe(socket, %{payment_intent_id: nil} = order) do
  case stripe_api().create_payment_intent(order) do
    {:ok, payment_intent} -> persist_payment_intent(socket, order, payment_intent)
    {:error, reason} -> stripe_create_failed(socket, order, reason)
  end
end
```

- [ ] Extract `persist_payment_intent/3` carrying the orphan-cancel logic
- [ ] Extract `stripe_create_failed/3` for the bare-flash path (or
      keep inline — judgment call)

---

### 6. Sub-section the `# Utilities` block

`# Utilities` at line 655 is a 200-line catch-all. The actual concepts:

| Concept | Lines (current) |
|---------|----------------|
| Forms (build, assign, submit, address bridge) | 684–742 |
| Order reload + fulfillment default | 744–778 |
| DOM helpers (next_section_id, scroll_to_state) | 783–791 |
| Stripe (already labelled) | 799–862 |

The `# Stripe utilities` sub-header at line 799 already exists; promote
the rest to match.

- [ ] Split `# Utilities` into `# Forms`, `# Order reload`,
      `# DOM helpers`, `# Stripe`
- [ ] Move helpers under the right header in source order

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

- **`size_label/1`** (lines 793–797) is only used by `card_drawer/1`.
  Lives in the right module today; if `card_drawer/1` ever moves to
  `CheckoutComponents`, `size_label/1` moves with it.
- **`<.card_drawer>` at line 332** sits inside `<Layouts.app>` but
  outside `<.container>`. Probably intentional (drawer escapes
  container's max-width) but worth confirming visually once.
