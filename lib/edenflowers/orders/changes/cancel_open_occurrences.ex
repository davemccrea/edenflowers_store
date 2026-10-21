defmodule Edenflowers.Orders.Changes.CancelOpenOccurrences do
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.ShopTime

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subscription -> cancel_open(subscription) end)
  end

  defp cancel_open(subscription) do
    query =
      Ash.Query.filter(
        Order,
        subscription_id == ^subscription.id and origin == :subscription and state == :placed and
          fulfillment_status == :pending
      )

    with {:ok, orders} <- Ash.read(query, authorize?: false) do
      orders
      |> Enum.filter(&cancellable?/1)
      |> Enum.reduce_while({:ok, subscription}, &cancel/2)
    end
  end

  defp cancel(order, result) do
    case Orders.cancel_order(order, authorize?: false) do
      {:ok, _order} -> {:cont, result}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp cancellable?(order) do
    deadline_date = order.subscription_date || order.fulfillment_date

    Date.after?(order.fulfillment_date, ShopTime.today()) and
      Subscription.changes_open_for?(deadline_date)
  end
end
