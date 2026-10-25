defmodule Edenflowers.Orders.Order.Changes.ClearPromotionFields do
  @moduledoc """
  Removes an order's promotion and the terms it copied from it. `fields/0`
  is the one list of them, shared with the checkout reset.
  """
  use Ash.Resource.Change

  @fields [
    :promotion_id,
    :discount_rate,
    :promotion_name,
    :promotion_code,
    :promotion_minimum_cart_total
  ]

  def fields, do: @fields

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attributes(changeset, Map.from_keys(@fields, nil))
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, Map.from_keys(@fields, nil)}
  end
end
