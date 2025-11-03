defmodule Edenflowers.Store.Order.UpdatePromotionUsageCount do
  @moduledoc """
  Updates promotion usage counter after an order is successfully finalized.

  This uses after_transaction to ensure:
  - Order finalization never fails due to promotion tracking issues
  - Promotion usage is updated via eventual consistency
  - Payment is always recorded even if promotion stats fail to update

  The hook runs AFTER the transaction commits, so the order is already persisted.
  If promotion update fails, it's logged but doesn't affect the order.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Store.Promotion

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      case result do
        {:ok, order} ->
          # Order successfully finalized - try to update promotion usage
          update_promotion_usage_async(order)
          result

        {:error, _error} ->
          # Order finalization failed - don't try to update promotion
          result
      end
    end)
  end

  defp update_promotion_usage_async(order) do
    case order.promotion_id do
      nil ->
        :ok

      promotion_id ->
        case Promotion.increment_usage(promotion_id, actor: system_actor()) do
          {:ok, _promotion} ->
            :ok

          {:error, error} ->
            Logger.error(
              "Failed to increment promotion usage for order #{order.id}, promotion #{promotion_id}: #{inspect(error)}"
            )

            # TODO: Enqueue reconciliation job to retry later
            :ok
        end
    end
  end
end
