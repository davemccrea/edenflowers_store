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
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.{HereAPI, Fulfillments}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option = Ash.Changeset.get_argument_or_attribute(changeset, :fulfillment_option)

      case fulfillment_option do
        nil ->
          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{field: :fulfillment_option})

        %{fulfillment_method: :delivery} ->
          handle_delivery(changeset, fulfillment_option)

        _ ->
          handle_pickup(changeset, fulfillment_option)
      end
    end)
  end

  defp handle_delivery(changeset, fulfillment_option) do
    with {:ok, delivery_address} <- get_delivery_address(changeset),
         {:ok, {calculated_address, position, here_id}} <- HereAPI.get_address(delivery_address),
         {:ok, distance} <- HereAPI.get_distance(position),
         {:ok, fulfillment_amount} <- Fulfillments.calculate_price(fulfillment_option, distance) do
      Ash.Changeset.force_change_attributes(changeset,
        fulfillment_amount: fulfillment_amount,
        delivery_address: delivery_address,
        calculated_address: calculated_address,
        position: position,
        here_id: here_id,
        distance: distance
      )
    else
      {:error, :delivery_address_is_empty} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{field: :delivery_address})

      {:error, :out_of_delivery_range} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: gettext("Outside delivery range")
        })

      {:error, :address_not_found} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: gettext("Address not found")
        })

      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: gettext("There was a problem calculating delivery cost, please try again later")
        })
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
          message: gettext("Unable to calculate fulfillment cost")
        })
    end
  end

  defp get_delivery_address(changeset) do
    case Ash.Changeset.get_argument_or_attribute(changeset, :delivery_address) do
      nil -> {:error, :delivery_address_is_empty}
      "" -> {:error, :delivery_address_is_empty}
      delivery_address -> {:ok, delivery_address}
    end
  end
end
