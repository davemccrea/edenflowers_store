defmodule Edenflowers.Store.Cart.Changes.UpdatePromotionUsageCount do
  @moduledoc """
  Updates promotion usage counter after a cart is successfully converted.

  Uses after_transaction to enqueue an Oban job that increments the promotion
  usage count. Conversion never fails due to promotion tracking issues —
  the cart and order are already persisted when this runs. Oban handles
  retries if the job fails.
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
        {:ok, cart} ->
          update_promotion_usage(cart)
          result

        {:error, _error} ->
          # Conversion failed - don't try to update promotion
          result
      end
    end)
  end

  defp update_promotion_usage(cart) do
    case cart.promotion_id do
      nil ->
        :ok

      promotion_id ->
        case IncrementPromotionUsage.enqueue(%{"promotion_id" => promotion_id}) do
          {:ok, _job} ->
            :ok

          {:error, error} ->
            Logger.error(
              "Failed to enqueue promotion usage increment for cart #{cart.id}, promotion #{promotion_id}: #{inspect(error)}"
            )

            :ok
        end
    end
  end
end
