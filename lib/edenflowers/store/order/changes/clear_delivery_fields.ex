defmodule Edenflowers.Store.Order.Changes.ClearDeliveryFields do
  use Ash.Resource.Change

  @fields [
    :delivery_address,
    :calculated_address,
    :position,
    :here_id,
    :distance,
    :fulfillment_amount
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attributes(changeset, Map.from_keys(@fields, nil))
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, Map.from_keys(@fields, nil)}
  end
end
