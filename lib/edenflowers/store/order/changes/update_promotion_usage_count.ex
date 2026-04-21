defmodule Edenflowers.Store.Order.UpdatePromotionUsageCount do
  @moduledoc """
  Updates promotion usage counter after an order is successfully finalized.

  Uses after_transaction to enqueue an Oban job that increments the promotion
  usage count. Order finalization never fails due to promotion tracking issues —
  the order is already persisted when this runs. Oban handles retries if the
  job fails.
  """
  use Ash.Resource.Change
  require Logger

  alias Edenflowers.Workers.IncrementPromotionUsage

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
          # Order finalization failed - don't try to update promotion
          result
      end
    end)
  end

  defp update_promotion_usage(order) do
    case order.promotion_id do
      nil ->
        :ok

      promotion_id ->
        case IncrementPromotionUsage.enqueue(%{"promotion_id" => promotion_id}) do
          {:ok, _job} ->
            :ok

          {:error, error} ->
            Logger.error(
              "Failed to enqueue promotion usage increment for order #{order.id}, promotion #{promotion_id}: #{inspect(error)}"
            )

            :ok
        end
    end
  end
end
