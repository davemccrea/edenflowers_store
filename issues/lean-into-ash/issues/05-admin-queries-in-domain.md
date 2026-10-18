# Move the admin's own query rules into the domain

Status: ready-for-agent
Type: refactor

## What to build

1. **Admin search.** `Admin.SearchLive` builds its own filters: which order fields are searchable (customer name, reference, phone, email, recipient name, delivery address) and which user fields (name, email). Make them `read :search` on `Order` and `User`, each with a `term` argument, based on `:admin_list`, and code interfaces `Orders.search_orders/2` and `Accounts.search_customers/2` taking the limit as a query option.
2. **Payments in date order.** `Admin.OrderDetailLive` and `Admin.CoursesLive` both load `payments: Payment |> Ash.Query.sort(paid_at: :asc) |> Ash.Query.load(:undoable?)`. Put `sort paid_at: :asc` on `has_many :payments` on both resources (or once in `Payable`, if `issues/payable-consolidation/` ticket 01 has moved it there), and load `payments: [:undoable?]`.
3. **Tax rates on the order form.** `Admin.OrderFormLive.tax_rates/2` reads every tax rate, then keeps in Elixir those whose percentage a custom line on the order already uses, alongside the selectable ones. Make the rule a read action on `TaxRate`, e.g. `read :for_order_form` with a `percentages` argument returning selectable rates plus those matching, behind a `Pricing` code interface.

## Tests

- A domain test per new read: search matches each field case-insensitively and respects the limit; the tax-rate read returns selectable rates plus a retired one in use.
- The existing LiveView tests pass unchanged.

## Acceptance criteria

- [ ] `SearchLive` and `OrderFormLive.tax_rates/2` build no `Ash.Query` themselves
- [ ] The existing suite passes

## Comments
