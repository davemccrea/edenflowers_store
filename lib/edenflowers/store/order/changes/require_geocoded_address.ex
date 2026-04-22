defmodule Edenflowers.Store.Order.RequireGeocodedAddress do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    # before_action so this only runs on submit, not on every phx-change validation.
    # geocoded_address is set server-side by the geocoding flow, not by user input,
    # so it would always appear missing while the user is typing.
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

      with {:ok, %{fulfillment_method: :delivery}} <-
             Ash.get(Edenflowers.Store.FulfillmentOption, fulfillment_option_id, authorize?: false) do
        geocoded_address = Ash.Changeset.get_attribute(changeset, :geocoded_address)
        fulfillment_amount = Ash.Changeset.get_attribute(changeset, :fulfillment_amount)

        if is_nil(geocoded_address) or is_nil(fulfillment_amount) do
          Ash.Changeset.add_error(changeset,
            field: :delivery_address,
            message: ~t"Please enter and confirm a delivery address"
          )
        else
          changeset
        end
      else
        _ -> changeset
      end
    end)
  end
end
