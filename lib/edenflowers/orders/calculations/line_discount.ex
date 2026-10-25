defmodule Edenflowers.Orders.Calculations.LineDiscount do
  @moduledoc """
  What the order's promotion takes off a line, rounded to cents line by line.

  `Actions.QuoteEntered` evaluates the same expression in memory, so a quote
  and the saved order agree.
  """
  use Ash.Resource.Calculation

  import Ash.Expr

  @impl true
  def expression(_opts, _context) do
    expr(if(promotion_applied?, do: round(subtotal * order.discount_rate, 2), else: 0))
  end
end
