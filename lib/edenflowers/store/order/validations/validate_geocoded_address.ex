defmodule Edenflowers.Store.Order.Validations.ValidateGeocodedAddress do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    method = Ash.Changeset.get_attribute(changeset, :fulfillment_method)
    geocoded_address = Ash.Changeset.get_attribute(changeset, :geocoded_address)

    if method == :delivery and is_nil(geocoded_address) do
      {:error, field: :delivery_address, message: ~t"Delivery address required"}
    else
      :ok
    end
  end
end
