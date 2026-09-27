defmodule Edenflowers.Orders.Order.Changes.CountPromotionUsage do
  use Ash.Resource.Change

  import Edenflowers.Actors

  alias Edenflowers.Pricing

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, promotion} <- Pricing.get_promotion_by_id(changeset.data.promotion_id, actor: system_actor()),
           {:ok, _promotion} <- Pricing.increment_promotion_usage(promotion, actor: system_actor()) do
        Ash.Changeset.force_change_attribute(changeset, :promotion_usage_counted_at, DateTime.utc_now())
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
