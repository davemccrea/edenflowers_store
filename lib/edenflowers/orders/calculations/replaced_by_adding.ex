defmodule Edenflowers.Orders.Calculations.ReplacedByAdding do
  @moduledoc """
  Whether adding a product replaces the cart: the cart holds only that product
  and either side is a subscription. A customer can then switch between buying
  once and subscribing, or change a subscription's size or frequency, without
  emptying the cart. A card in the cart is never replaced.

  `replaces?/3` is the same rule over line items already in hand, so the
  product page can ask on every render without a query.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [line_items: [:is_card, :product_id, :interval_weeks]]

  @impl true
  def calculate(orders, _opts, %{arguments: %{product_id: product_id, subscription?: subscription?}}) do
    Enum.map(orders, &replaces?(&1.line_items, product_id, subscription?))
  end

  def replaces?(line_items, product_id, subscription?) do
    lines = Enum.reject(line_items, & &1.is_card)

    lines != [] and Enum.all?(lines, &(&1.product_id == product_id)) and
      (subscription? or Enum.any?(lines, & &1.interval_weeks))
  end
end
