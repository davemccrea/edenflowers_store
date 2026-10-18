---
id: TASK-10.1
title: Animate cart row removal
status: done
assignee: []
created_date: '2026-10-15 23:06'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-10
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

When a cart row is removed, the remaining rows snap up. Fade the removed row out and collapse it, so the rows below slide into place.

Use LiveView's `phx-remove` on each row in `lib/edenflowers_web/components/cart/line_items.ex`. No JS library. See Comments for how it works.

#### Not doing

- **Enter animation for added items.** On the product page, an add opens the drawer straight from the event reply (`product_live.ex` `handle_event("submit", ...)`). The new row then arrives through the `HandleLineItemChanged` PubSub broadcast, during the drawer's 250ms slide-in (`--drawer-duration`). Any row animation would play underneath the slide, so the slide is the add feedback. A CSS `@starting-style` enter rule can't be used either. The `<dialog>` is `display: none` while closed, so the rule would fire for every row each time the drawer opens.
- **Pulsing the cart count.** The header badge sits behind the drawer's backdrop when you add from the product page, so nobody would see it.
- **Removing the last item.** That swaps the list for the empty state, so the whole `<ul>` and its hook are removed with no animation. The confirm dialog already slows that moment down.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Removing a middle row with trash fades that row out, and the rows below slide up
- [ ] #2 Removing the card add-on does the same
- [x] #3 Quickly removing two rows leaves the correct rows with no leftover ghost row
- [x] #4 With "Reduce motion" turned on, rows are removed instantly
- [x] #5 The drawer opens and closes as it does now
- [x] #6 Existing cart and checkout tests pass
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-17 16:08

---

Implemented without auto-animate. The first version used it, but it fought LiveView: morphdom pulled the links and images out of the row auto-animate was fading, and the hook had to snapshot and refill rows. Replaced with LiveView's own `phx-remove`:

- A row with `phx-remove` is skipped by morphdom's discard, kept in place with clicks silenced, and removed by LiveView after its exit transition.
- `collapse_row/0` is a `JS.hide` that fades the row and collapses it from `grid-rows-[1fr]` to `grid-rows-[0fr]`, so the rows below glide up. Reduced motion skips the transition.
- Each row owns its bottom spacing (`pb-5` inside a `min-h-0` wrapper, cancelled on the list by `-mb-5`), so the spacing collapses with the row instead of snapping.
- The row's links and images have ids. Without them morphdom matches them by `data-phx-id` to the row that takes this one's place, and pulls them out of the row that's fading.

Decrement stops at 1 (`LineItem :decrement_quantity`), so it never removes a row and that criterion was dropped. No add animation: the new row arrives during the drawer's slide-in, so the slide is the feedback.

Dropped: not worth the complexity. Every approach needed workarounds for how LiveView patches the list.

---
<!-- COMMENTS:END -->
