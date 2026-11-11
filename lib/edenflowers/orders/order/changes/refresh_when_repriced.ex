defmodule Edenflowers.Orders.Order.Changes.RefreshWhenRepriced do
  @moduledoc """
  Keeps a placed order's stored grand total and VAT breakdown true to its fees
  and promotion whenever an update changes one, whichever action does it
  (ADR 0007). Placing an order snapshots them itself.
  """
  use Ash.Resource.Change

  alias Edenflowers.Orders

  @priced_by [
    :quoted_fulfillment_fee,
    :quoted_free_delivery_fee,
    :fulfillment_fee_override,
    :fulfillment_tax_rate,
    :promotion_id,
    :discount_rate,
    :promotion_minimum_cart_total
  ]

  @impl true
  def change(changeset, _opts, _context) do
    # Checked once saved, as PriceFulfillment sets the fees in a hook.
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      if order.state == :placed and sets_price?(changeset),
        do: Orders.refresh_vat_breakdown(order, authorize?: false),
        else: {:ok, order}
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp sets_price?(changeset) do
    Enum.any?(@priced_by, &(Map.has_key?(changeset.attributes, &1) or Keyword.has_key?(changeset.atomics, &1)))
  end
end
