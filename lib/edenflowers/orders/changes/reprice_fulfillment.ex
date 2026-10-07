defmodule Edenflowers.Orders.Changes.RepriceFulfillment do
  @moduledoc """
  Reprices a delivery at its stored distance after the order's lines change,
  since whether the cart holds a free-delivery product changes the fee. An
  order with no stored distance, or with Jennie's own fee, is left alone.

  Reads the order afresh and writes the fee atomically: callers may hold an
  order from before the cart last changed, and a plain change to a fee equal
  to that stale one would be skipped as unchanged.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.Fee

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &reprice/1)
  end

  defp reprice(changeset) do
    order =
      changeset.data
      |> Ash.reload!(authorize?: false)
      |> Ash.load!([:free_delivery?, :fulfillment_option], authorize?: false)

    with %{fulfillment_method: :delivery, distance: distance, fulfillment_fee_override: nil} when is_integer(distance) <-
           order,
         %{error: nil, fulfillment_fee: fee} <- Fee.calculate(order.fulfillment_option, distance, order.free_delivery?) do
      Ash.Changeset.atomic_update(changeset, :fulfillment_fee, fee)
    else
      _ -> changeset
    end
  end
end
