defmodule Edenflowers.Orders.Changes.CancelOpenOccurrences do
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Expressions.HelsinkiToday
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{Order, Subscription}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subscription ->
      query =
        Ash.Query.filter(
          Order,
          subscription_id == ^subscription.id and origin == :subscription and state == :placed and
            fulfillment_status == :pending
        )

      with {:ok, orders} <- Ash.read(query, authorize?: false) do
        orders
        |> Enum.filter(&cancellable?/1)
        |> Enum.reduce_while({:ok, subscription}, fn order, result ->
          case Orders.cancel_order(order, authorize?: false) do
            {:ok, _order} -> {:cont, result}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
      end
    end)
  end

  defp cancellable?(order) do
    deadline_date = order.subscription_date || order.fulfillment_date

    Date.after?(order.fulfillment_date, HelsinkiToday.today()) and
      Subscription.changes_open_for?(deadline_date)
  end
end
