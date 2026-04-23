defmodule Edenflowers.Store.Order.Changes.RequireGeocodedAddress do
  @moduledoc """
  Guards step 3 submission for delivery orders: the address must have been
  geocoded (by the blur handler on the checkout form) before we accept the
  submit.

  Runs `before_action` rather than during `validate` because `geocoded_address`
  is written server-side from the HERE API response, not from form params, so
  it would always look missing during phx-change while the user is typing.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if delivery?(changeset) and not geocoded?(changeset) do
        Ash.Changeset.add_error(changeset,
          field: :delivery_address,
          message: ~t"Delivery address required"
        )
      else
        changeset
      end
    end)
  end

  defp delivery?(changeset) do
    Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery
  end

  defp geocoded?(changeset) do
    not is_nil(Ash.Changeset.get_attribute(changeset, :geocoded_address)) and
      not is_nil(Ash.Changeset.get_attribute(changeset, :fulfillment_amount))
  end
end
