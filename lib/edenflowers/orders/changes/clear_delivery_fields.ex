defmodule Edenflowers.Orders.Changes.ClearDeliveryFields do
  @moduledoc """
  Blanks everything derived from a delivery address. `fields/0` is the one
  list of them, shared with the pickup cost and the checkout reset.
  """
  use Ash.Resource.Change

  @fields [
    :delivery_address,
    :delivery_instructions,
    :geocoded_address,
    :position,
    :here_id,
    :distance,
    :fulfillment_fee
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
