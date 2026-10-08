# Admin table consistency

The admin tables share one Cinder theme and page size, but each page invented its own behaviour for search, filters, sorting, alignment, empty cells, yes/no values and phone layout. Bring them under one set of rules, applied page by page. No shared `admin_table` wrapper: the divergence is in the columns, which a wrapper would not fix.

Tables in scope: orders, customers, customer detail (orders), subscriptions, expenses, promotions, products.

## Rules

1. **Search.** Every list page configures `search={[label:, placeholder:, fn:]}` with a placeholder naming what it searches ("Search name or email…"). The customer detail order list is exempt (it is already scoped to one customer).
2. **Filters.** Every enum or category column has a select filter, with a caption set via the filter's `:label` and `prompt: ~t"All"`. Pages with filters use `show_filters={:toggle}`.
3. **Sorting.** Every column backed by a field is sortable. Date columns cycle `[:desc, :asc]` (newest first), except schedule dates (order fulfillment date, subscription next delivery), which cycle `[:asc, :desc]`: soonest first is what Jennie works from.
4. **Alignment.** Every numeric column (money, counts, percentages, usage) is `text-right` with `tabular-nums`.
5. **Empty values.** A cell whose value can be nil renders `<.blank />`. Non-nullable fields need no guard.
6. **Yes/no values.** An icon for yes (with `sr-only` text), `<.blank />` for no. Named states with more meaning than yes/no (product Draft/Published, subscription state, order statuses) stay badges.
7. **Phone layout.** Columns hidden with `max-sm:hidden` are folded into the primary cell as a muted secondary line with `sm:hidden`, following the existing expenses table. Nothing a desktop row shows is lost on a phone.
8. **Primary column.** The first visible column identifies the record and links to its detail page (`font-medium hover:underline`). Every table has a row `click` to the same page.
9. **No row actions.** Actions live on the detail page, not in table rows.
