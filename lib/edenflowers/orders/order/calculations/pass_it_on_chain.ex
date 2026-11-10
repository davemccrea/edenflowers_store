defmodule Edenflowers.Orders.Order.Calculations.PassItOnChain do
  @moduledoc """
  The tree of orders connected through pass-it-on cards, source before redemption.
  Walk back to the source, then visit every live redemption of each card.
  Checkout can overuse a one-use code concurrently, so retain every branch.

  Cancelled redemptions are omitted unless they connect surviving orders or
  are the order being viewed, so recorded sources always remain traceable.
  """
  use Ash.Resource.Calculation

  @link_load [promotion: [:card_status, gift_order: []], pass_it_on_card: [:card_status, :placed_orders]]

  defstruct [:nodes, :multiple?, :visible?]

  @impl true
  def load(_query, _opts, _context), do: @link_load

  @impl true
  def calculate(orders, _opts, context) do
    # The chain has no fixed depth, so each node's links are loaded as they are
    # discovered. `load/3` preloads the first links in one batched query, and
    # `reuse_values?` stops `chain/2` reading them again.
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:reuse_values?, true)
    Enum.map(orders, &chain(&1, opts))
  end

  defp chain(order, opts) do
    order = Ash.load!(order, @link_load, opts)
    root = source(order, MapSet.new([order.id]), opts)
    {nodes, _seen} = forward(root, order.id, MapSet.new(), opts)
    multiple? = length(nodes) > 1 or Enum.any?(nodes, &(&1.children != []))

    %__MODULE__{
      nodes: nodes,
      multiple?: multiple?,
      visible?: multiple? or not is_nil(order.pass_it_on_card) or match?(%{kind: :pass_it_on}, order.promotion)
    }
  end

  defp source(%{promotion: %{kind: :pass_it_on, gift_order: %{state: :placed} = gift}} = order, seen, opts) do
    if MapSet.member?(seen, gift.id) do
      order
    else
      gift = Ash.load!(gift, @link_load, opts)
      source(gift, MapSet.put(seen, gift.id), opts)
    end
  end

  defp source(order, _seen, _opts), do: order

  # Seen ids bound both directions even if historical data contains a cycle.
  defp forward(order, current_id, seen, opts) do
    if MapSet.member?(seen, order.id) do
      {[], seen}
    else
      order = Ash.load!(order, @link_load, opts)

      {branches, seen} =
        Enum.reduce(brought_in(order), {[], MapSet.put(seen, order.id)}, fn next, {chain, seen} ->
          {branch, seen} = forward(next, current_id, seen, opts)
          {chain ++ branch, seen}
        end)

      if order.fulfillment_status == :cancelled and order.id != current_id and branches == [],
        do: {[], seen},
        else: {[%{order: order, children: branches}], seen}
    end
  end

  defp brought_in(%{pass_it_on_card: %{kind: :pass_it_on, placed_orders: orders}}) do
    Enum.sort_by(orders, &{&1.ordered_at && DateTime.to_unix(&1.ordered_at, :microsecond), &1.id})
  end

  defp brought_in(_order), do: []
end
