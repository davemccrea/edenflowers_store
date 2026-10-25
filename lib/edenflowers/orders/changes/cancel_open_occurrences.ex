defmodule Edenflowers.Orders.Changes.CancelOpenOccurrences do
  @moduledoc """
  Cancels future, still-open Occurrences when their subscription ends. Each
  order uses the normal cancellation path, including any required refund.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order

  @impl true
  # After the transaction, so each order's Stripe refund runs outside the
  # subscription's transaction and a rollback can't undo the DB side alone.
  def change(changeset, _opts, context) do
    cancelled_by = if context.actor && context.actor.admin, do: :shop, else: :customer

    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, subscription} -> cancel_open(subscription, cancelled_by)
      _changeset, error -> error
    end)
  end

  defp cancel_open(subscription, cancelled_by) do
    query =
      Ash.Query.filter(
        Order,
        subscription_id == ^subscription.id and origin == :subscription and cancellable? and changes_open?
      )

    with {:ok, orders} <- Ash.read(query, authorize?: false) do
      Enum.reduce_while(orders, {:ok, subscription}, &cancel(&1, &2, cancelled_by))
    end
  end

  defp cancel(order, result, cancelled_by) do
    case Orders.cancel_order(order, %{cancelled_by: cancelled_by}, authorize?: false) do
      {:ok, _order} -> {:cont, result}
      {:error, error} -> {:halt, {:error, error}}
    end
  end
end
