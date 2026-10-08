# Apply the table rules to every admin table

Status: ready-for-agent
Blocked by: 01

Apply the rules in `../spec.md` to each table. Known gaps per page:

## Orders (`orders_live.ex`)
- Primary column is fulfillment date; make customer the first column (rule 8). Fulfillment date keeps its `[:asc, :desc]` cycle.
- Total is not sortable (rule 3).
- Fold Payment and Method into the primary cell on phones (rule 7).

## Customers (`customers_live.ex`)
- Orders count is left-aligned (rule 4).
- Fold Total spent and Last order into the primary cell on phones (rule 7).

## Customer detail orders (`customer_detail_live.ex`)
- Fulfillment, Payment, Total and Method are not sortable (rule 3).
- Payment shows on phones here but is hidden on the orders page; hide it and fold hidden columns into the primary cell (rule 7).
- Fulfillment date sorts with the default cycle; use `[:desc, :asc]` (rule 3).

## Subscriptions (`subscriptions_live.ex`)
- No search; add one over customer name and email (rule 1).
- No filters; add a State filter, `show_filters={:toggle}` (rule 2).
- Customer and Size are not sortable (rule 3).
- Next delivery uses the default sort cycle; it is a schedule like order fulfillment date, so use `[:asc, :desc]` (rule 3).

## Expenses (`expenses_live.ex`)
- Date column comes first and is hidden on phones; make vendor the first column (rule 8).
- Date uses the default sort cycle; use `[:desc, :asc]` (rule 3).
- Confidence is not sortable (rule 3).
- Reviewed renders a check + "Reviewed" or "Not reviewed"; use the check icon with `sr-only` text, `<.blank />` when not reviewed (rule 6). Same in the phone secondary line.
- Move `theme=` after `page_size=` to match the attribute order of the other tables.

## Promotions (`promotions_live.ex`)
- Search uses Cinder's default box; configure label, placeholder ("Search name or code…") and `fn` (rule 1).
- Discount and Used are left-aligned (rule 4).
- Start and expiry dates use the default sort cycle; use `[:desc, :asc]` (rule 3).
- Fold Minimum, Starts, Expires and Used into the primary cell on phones (rule 7).

## Products (`products_live.ex`)
- Search uses Cinder's default box; configure label, placeholder and `fn` (rule 1).
- Featured and Subscription render nothing for "no"; add `<.blank />` (rule 6).
- Fold Category, Featured and Subscription into the primary cell on phones (rule 7).

## Acceptance

- Every table meets every rule in the spec, or the spec records the exception.
- Existing admin LiveView tests pass; add tests for the new searches (subscriptions, promotions, products) and the subscription State filter.
