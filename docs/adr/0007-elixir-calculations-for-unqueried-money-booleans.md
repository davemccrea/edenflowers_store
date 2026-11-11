# Unqueried booleans over the Balance are computed in Elixir

Calculations are Ash expressions by default. One definition then works in a filter, a sort, an aggregate and a load, and reads in the same language as its neighbours.

The exception is a calculation that builds on the Balance chain (`balance`, `payment_status`, `settled?`, `payable?`, an invoice's status) when nothing filters, sorts or aggregates on it. That one is computed in Elixir: an inline function in the resource, with `load` naming the values it reads. `to_collect?`, `refundable?`, `unpaid?`, `receipt_available?` and `payment_instruction` are examples.

Ash inlines an expression calculation into the SQL of every expression that references it, with no way to compute it once. The Balance expands the grand total five times on its own, so each boolean over it carried another copy. The admin order page's read reached 65 KB of SQL with 558 bind parameters and 67 copies of the grand total. The whole read spent about 20 ms in Postgres locally, but about 75 ms in Elixir building the query, and building it was most of the read's 470–615 ms in production. With the booleans computed from values loaded once, the read fell from 97 ms to 42 ms locally, and Postgres time didn't change.

## Considered Options

- **Keep every calculation an expression.** Rejected: the cost grows with each boolean added over the Balance, and every read of an order pays it.
- **Compute every derived calculation in Elixir.** Rejected: a calculation computed in Elixir can't be filtered, sorted or aggregated on, and the ones that are (`settled?`, `payable?`, `payment_status`, `payment_link_open?`, `holds_money?`) must stay in SQL.
- **One module per calculation** (`use Ash.Resource.Calculation`). Tried first, then inlined: two dozen files of one or two lines each kept each rule away from the expressions it derives from. A module is still right for logic too long to read inside the resource, like `AdminMenuActions`.
- **Store the grand total or Balance as a column.** Not taken yet: it removes the chain entirely, but every change to an order would have to keep the stored value up to date.

## Consequences

- A new calculation starts as an expression. It moves to Elixir only when it builds on the Balance chain, nothing queries it, and the read it's loaded in is measurably slower for it.
- Filtering, sorting or aggregating on one computed in Elixir raises an error. If one is ever needed in a query, turn it back into an expression and accept the cost.
- One that restates an expression it no longer references (`to_collect?` and `to_refund?` restate `settled?`; `unpaid?` restates `payable?`) says so in a comment, and changes with that expression.
- The rule stays in the resource, with its description, so the UI reads it as a calculation either way.
