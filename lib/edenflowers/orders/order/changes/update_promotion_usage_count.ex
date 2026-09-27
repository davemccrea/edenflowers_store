defmodule Edenflowers.Orders.Order.Changes.UpdatePromotionUsageCount do
  @moduledoc """
  Schedules promotion usage accounting after an order is successfully finalized.

  The trigger's periodic scheduler repairs a failed enqueue, so order finalization
  never fails due to promotion tracking issues.
  """
  use Ash.Resource.Change
  require Logger

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      case result do
        {:ok, order} ->
          update_promotion_usage(order)
          result

        {:error, _error} ->
          result
      end
    end)
  end

  defp update_promotion_usage(order) do
    case order.promotion_id do
      nil ->
        :ok

      promotion_id ->
        try do
          AshOban.run_trigger(order, :count_promotion_usage)
          :ok
        rescue
          error ->
            Logger.error(
              "Failed to schedule promotion usage increment for order #{order.id}, promotion #{promotion_id}: #{Exception.message(error)}"
            )

            :ok
        end
    end
  end
end
