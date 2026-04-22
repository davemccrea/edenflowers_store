defmodule Edenflowers.Store.Order.ValidateAndCalculateFulfillment do
  @moduledoc """
  Validates fulfillment options and calculates delivery costs.

  For delivery orders:
  - Validates and geocodes delivery address using HereAPI
  - Calculates distance from store to delivery location
  - Computes delivery cost based on distance

  For pickup orders:
  - Calculates fixed pickup price
  - Clears delivery-related fields
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

      case fulfillment_option_id do
        nil ->
          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{field: :fulfillment_option})

        id ->
          case Ash.get(Edenflowers.Store.FulfillmentOption, id, authorize?: false) do
            {:ok, %{fulfillment_method: :delivery}} ->
              handle_delivery(changeset)

            {:ok, fulfillment_option} ->
              handle_pickup(changeset, fulfillment_option)

            {:error, _} ->
              Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
                field: :fulfillment_option_id,
                message: "Invalid fulfillment option"
              })
          end
      end
    end)
  end

  defp handle_delivery(changeset) do
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)
    calculated_address = Ash.Changeset.get_attribute(changeset, :calculated_address)
    fulfillment_amount = Ash.Changeset.get_attribute(changeset, :fulfillment_amount)

    address_blank? = is_nil(delivery_address) or String.trim(delivery_address) == ""

    # ConfirmDeliveryAddress writes delivery_address alongside its geocode data atomically,
    # so the persisted delivery_address always matches the persisted geocode. On save_step_3
    # submit, the incoming delivery_address param can differ from the persisted value — that
    # means the user edited the field without blurring to confirm, so the geocode is stale.
    geocode_stale? =
      not address_blank? and
        delivery_address != changeset.data.delivery_address

    changeset =
      if address_blank? or geocode_stale? do
        Ash.Changeset.force_change_attributes(changeset,
          calculated_address: nil,
          position: nil,
          here_id: nil,
          distance: nil,
          fulfillment_amount: nil
        )
      else
        changeset
      end

    if address_blank? or geocode_stale? or is_nil(calculated_address) or is_nil(fulfillment_amount) do
      Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
        field: :delivery_address,
        message: ~t"Please enter and confirm a delivery address"
      })
    else
      changeset
    end
  end

  defp handle_pickup(changeset, fulfillment_option) do
    case Fulfillments.calculate_price(fulfillment_option) do
      {:ok, fulfillment_amount} ->
        Ash.Changeset.force_change_attributes(changeset,
          fulfillment_amount: fulfillment_amount,
          delivery_address: nil,
          delivery_instructions: nil,
          calculated_address: nil,
          position: nil,
          here_id: nil,
          distance: nil
        )

      {:error, _reason} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :fulfillment_option_id,
          message: ~t"Unable to calculate fulfillment cost"
        })
    end
  end
end
