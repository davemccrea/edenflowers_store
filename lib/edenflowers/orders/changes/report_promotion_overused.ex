defmodule Edenflowers.Orders.Changes.ReportPromotionOverused do
  @moduledoc """
  A code's usage limit is checked when it is applied, so two carts holding the
  same code can both be placed. The customer has paid by then, so the order is
  placed anyway and the overuse is logged as an error so it reaches ErrorTracker.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Pricing

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      if order.promotion_id, do: check_usage(order)
      {:ok, order}
    end)
  end

  defp check_usage(order) do
    promotion = Pricing.get_promotion_by_id!(order.promotion_id, load: [:usage], authorize?: false)

    if promotion.usage_limit && promotion.usage > promotion.usage_limit do
      Logger.error(
        "Order #{order.id} placed with promotion #{promotion.code} past its usage limit " <>
          "(#{promotion.usage} uses, limit #{promotion.usage_limit})."
      )
    end
  end
end
