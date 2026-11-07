defmodule Edenflowers.Orders.Order.Calculations.PassItOnChain do
  @moduledoc """
  The run of orders an order belongs to through pass-it-on cards, oldest first:
  back through the gift whose card each order was placed with, then forward
  through each gift's card to the order it brought in. Each order comes with its
  card, if one went with it.

  A cancelled order brought nothing in, so the chain doesn't run through one.
  A card can only be used once, so it never branches.
  """
  use Ash.Resource.Calculation

  alias Edenflowers.Orders.Order

  @link_load [promotion: [], pass_it_on_card: [:card_status, :placed_orders]]

  @impl true
  def calculate(orders, _opts, context) do
    opts = Ash.Context.to_opts(context)
    Enum.map(orders, &chain(&1, opts))
  end

  defp chain(order, opts) do
    order = Ash.load!(order, @link_load, opts)
    back(order, [order], MapSet.new([order.id]), opts)
  end

  # The seen ids only guard against a loop in bad data, which would hang the page.
  defp back(%{promotion: %{gift_order_id: id}}, chain, seen, opts) when is_binary(id) do
    if MapSet.member?(seen, id) do
      forward(List.last(chain), chain, seen, opts)
    else
      gift = Ash.get!(Order, id, Keyword.put(opts, :load, @link_load))
      back(gift, [gift | chain], MapSet.put(seen, id), opts)
    end
  end

  defp back(_order, chain, seen, opts), do: forward(List.last(chain), chain, seen, opts)

  defp forward(order, chain, seen, opts) do
    case brought_in(order) do
      %{id: id} = next ->
        if MapSet.member?(seen, id) do
          chain
        else
          next = Ash.load!(next, @link_load, opts)
          forward(next, chain ++ [next], MapSet.put(seen, id), opts)
        end

      nil ->
        chain
    end
  end

  defp brought_in(%{pass_it_on_card: %{placed_orders: orders}}),
    do: Enum.find(orders, &(&1.fulfillment_status != :cancelled))

  defp brought_in(_order), do: nil
end
