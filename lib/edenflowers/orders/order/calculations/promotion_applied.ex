defmodule Edenflowers.Orders.Order.Calculations.PromotionApplied do
  @moduledoc """
  Whether an order's promotion discounts it. A code stays on the order when
  the cart drops below its minimum, but only discounts while the cart meets it.

  `Actions.QuoteEntered` evaluates the same expression in memory, so a quote
  and the saved order agree.
  """
  use Ash.Resource.Calculation

  import Ash.Expr

  @impl true
  def expression(_opts, _context) do
    expr(
      not is_nil(promotion_id) and
        (is_nil(promotion_minimum_cart_total) or items_subtotal >= promotion_minimum_cart_total)
    )
  end
end
