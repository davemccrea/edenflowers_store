defmodule Edenflowers.Store.Order.Changes.ClearGeocodeIfDiverged do
  @moduledoc """
  Clears the persisted geocode when the user's typed address has diverged
  from the confirmed one, so a submit can't sneak through using a stale geocode.

  Takes a `:typed_address` argument and compares it to the persisted
  `delivery_address`. No-op if nothing was confirmed yet or the values match.
  """
  use Ash.Resource.Change

  @cleared_fields [
    :delivery_address,
    :geocoded_address,
    :position,
    :here_id,
    :distance,
    :fulfillment_amount
  ]

  @impl true
  def change(changeset, _opts, _context) do
    typed = Ash.Changeset.get_argument(changeset, :typed_address) || ""
    persisted = Ash.Changeset.get_attribute(changeset, :delivery_address)
    geocoded = Ash.Changeset.get_attribute(changeset, :geocoded_address)

    if not is_nil(geocoded) and String.trim(typed) != persisted do
      Ash.Changeset.force_change_attributes(changeset, Map.from_keys(@cleared_fields, nil))
    else
      changeset
    end
  end
end
