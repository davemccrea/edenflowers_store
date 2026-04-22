defmodule Edenflowers.Store.Order.RequireGeocodedAddress do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    with {:ok, %{fulfillment_method: :delivery}} <-
           Ash.get(Edenflowers.Store.FulfillmentOption, fulfillment_option_id, authorize?: false) do
      geocoded_address = Ash.Changeset.get_attribute(changeset, :geocoded_address)
      fulfillment_amount = Ash.Changeset.get_attribute(changeset, :fulfillment_amount)

      if is_nil(geocoded_address) or is_nil(fulfillment_amount) do
        {:error,
         field: :delivery_address,
         message: ~t"Please enter and confirm a delivery address"}
      else
        :ok
      end
    else
      _ -> :ok
    end
  end
end
