# Native "More actions" menu

Status: ready-for-agent

The order detail, promotion form and subscription detail pages each have their own copy of a ⋯ "More actions" menu built on daisyUI's focus-based `dropdown`. It was right-aligned to its trigger, so on phones, where the header actions wrap to the left edge under the title, it opened off-screen. The stopgap is `dropdown sm:dropdown-end`, which only works because the trigger happens to sit at the left on phones.

Replace the three copies with one `actions_menu` component in `EdenflowersWeb.Admin.Components` built on the Popover API and CSS anchor positioning, which daisyUI 5's dropdown supports.

## What to build

- Trigger: the existing `icon_button` with `aria_label={~t"More actions"}` and `popovertarget`, given an `anchor-name`.
- Menu: `<ul popover id=… class="dropdown menu …">` with `position-anchor` set to the trigger, end-aligned, and `position-try-fallbacks: flip-inline` so it opens towards whichever side has room. Keep the current look (`bg-base-100 border-base-300 border p-1 shadow`, width per menu).
- Items close the menu when chosen: each item button gets `popovertarget={menu id}` and `popovertargetaction="hide"` alongside its `phx-click`. No custom JS.
- Declining a `data-confirm` must leave the menu open. `phoenix_html`'s click handler calls `preventDefault()` on a declined confirm, which skips the button's popover-hide behaviour. Confirm which handler actually serves `data-confirm` in this app (`assets/js/app.js` doesn't mention it) and check the behaviour.
- The order menu's disabled items with a reason (`unavailable_menu_item`) keep working.
- Drop `sm:dropdown-end` and `z-10` from the three call sites; the popover sits in the top layer.

## Call sites

- `order_detail_live.ex`: `order_menu`
- `promotion_form_live.ex`: Delete
- `subscription_detail_live.ex`: Cancel subscription

The account menu in `layouts.ex` sits at the top right and is out of scope.

## Acceptance

- On a phone and on desktop the menu opens fully on-screen wherever the trigger sits.
- Choosing an item runs its action and closes the menu; declining its confirm leaves the menu open.
- Clicking outside and pressing Esc close the menu, and focus returns to the trigger.
- Existing order, promotion and subscription detail tests pass.
