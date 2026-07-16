defmodule Edenflowers.Orders.LineItem.Checks.OrderNotPlaced do
  @moduledoc """
  Authorizes a LineItem create only when the target Order is still in checkout.
  Filter-expression checks (`forbid_if expr(order.state == :placed)`) cannot be
  used on creates because there is no row to filter; this check resolves the
  related order at policy-evaluation time instead.
  """
  use Ash.Policy.SimpleCheck

  alias Edenflowers.Orders.Order

  @impl true
  def describe(_opts), do: "order is not in :placed state"

  @impl true
  def match?(_actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :order_id) do
      nil ->
        false

      order_id ->
        case Ash.get(Order, order_id, authorize?: false) do
          {:ok, %{state: :placed}} -> false
          {:ok, _} -> true
          {:error, _} -> false
        end
    end
  end

  def match?(_, _, _), do: false
end
