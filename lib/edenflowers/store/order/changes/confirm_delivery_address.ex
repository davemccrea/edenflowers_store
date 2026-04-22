defmodule Edenflowers.Store.Order.Changes.ConfirmDeliveryAddress do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      address = Ash.Changeset.get_argument(changeset, :address)
      fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

      with {:ok, fulfillment_option} <- FulfillmentOption.get_by_id(fulfillment_option_id, authorize?: false),
           {:ok, result} <- Fulfillments.calculate_delivery(address, fulfillment_option) do
        Ash.Changeset.force_change_attributes(changeset,
          delivery_address: address,
          geocoded_address: result.geocoded_address,
          position: result.position,
          here_id: result.here_id,
          distance: result.distance,
          fulfillment_amount: result.fulfillment_amount
        )
      else
        {:error, :address_not_found} ->
          Ash.Changeset.add_error(changeset, field: :delivery_address, message: ~t"Address not found")

        {:error, :out_of_delivery_range} ->
          Ash.Changeset.add_error(changeset, field: :delivery_address, message: ~t"Outside delivery range")

        {:error, _} ->
          Ash.Changeset.add_error(changeset,
            field: :delivery_address,
            message: ~t"There was a problem calculating delivery cost, please try again later"
          )
      end
    end)
  end
end
