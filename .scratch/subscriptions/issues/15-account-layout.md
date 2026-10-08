# Account page layout and links

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items A5, A10, A12, A17 and A18 in `10-ux-audit.md`. Subscriptions stays its own section (see the audit's "Account page structure"), moves up, and links to Orders.

## Acceptance criteria

- [x] **A5.** Each row shows recipient and address: "To Ingrid Nyman, Gerbyntie 16, Vaasa", with "To change the address, contact us."
- [x] **A10.** Subscriptions sits above "Your details". Each row leads with its status sentence at body size; size and frequency sit behind a **Change** button.
- [x] **A12.** A cancelled subscription offers "Start a new subscription" linking to the subscription product.
- [x] **A17.** With no subscriptions, the section shows a one-line prompt linking to the subscription product, like Orders and Courses.
- [x] **A18.** Orders marks subscription deliveries with a "Subscription" label; each subscription row links to its "Past deliveries".
- [x] Strings translated (sv, fi). Tests for the empty state, recipient line and label.

## Blocked by

- `12-account-status.md`
- `13-account-actions.md`

## Comments

**Built (slice 15), reworked with David's review**

- Subscriptions is now a table under Orders, with the same column widths: Plan | Next delivery | Price | Manage. **Your details** stays first. This overrides A10's "move above Your details", at David's request.
- **Manage** opens a right-hand drawer (the cart's `.drawer`) with hairline-ruled rows:
  - Next delivery (with skip/unskip and pause/resume)
  - Plan (with a **Change** toggle revealing size/frequency)
  - Delivers to (recipient and address, plus "Moving? Contact us to change the address.")
  - Card
  - Cancel subscription, pinned to the bottom
- Action outcomes show in the drawer as a cream notice, since the page flash sits under the modal.
- Empty state: one line plus "See the subscription", linking to the first subscribable store product.
- Cancelled: "Start a new subscription" in the drawer, linking to the product page.
- Orders mark subscription deliveries with "Subscription".
- Dropped: the "Past deliveries" link. The Subscription label in Orders does that job, and the link added clutter.
- Checked in the browser at 1440 and 390 px.
