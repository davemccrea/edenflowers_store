defmodule Edenflowers.Store.Order.ValidateAndCalculateFulfillment do
  @moduledoc """
  Validates fulfillment options and calculates fulfillment costs on submit.

  For delivery orders:
  - Verifies the address was already geocoded (by ConfirmDeliveryAddress on blur)
  - Rejects submission if calculated_address or fulfillment_amount is missing

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
    calculated_address = Ash.Changeset.get_attribute(changeset, :calculated_address)
    fulfillment_amount = Ash.Changeset.get_attribute(changeset, :fulfillment_amount)

    if is_nil(calculated_address) or is_nil(fulfillment_amount) do
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
