defmodule Edenflowers.Fulfillment.Actions.CalculateDelivery do
  @moduledoc """
  Geocodes a delivery address and prices it with the option's fee rules. An
  undeliverable address is a normal result, returned as `%{error: reason}`.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Fee

  @impl true
  def run(input, _opts, _context) do
    %{delivery_address: delivery_address, fulfillment_option_id: option_id} = input.arguments

    with {:ok, option} <- Fulfillment.get_option_by_id(option_id, authorize?: false),
         {:ok, {geocoded_address, position, here_id}} <- here_api().geocode(delivery_address),
         {:ok, distance} <- here_api().route_distance(position) do
      case Fee.calculate(option, distance) do
        %{error: nil} = fee ->
          {:ok,
           %{
             error: nil,
             geocoded_address: geocoded_address,
             position: position,
             here_id: here_id,
             distance: distance,
             fulfillment_fee: fee.fulfillment_fee,
             in_free_delivery_zone: fee.in_free_delivery_zone
           }}

        %{error: reason} ->
          {:ok, %{error: reason}}
      end
    else
      {:error, reason} -> {:ok, %{error: reason}}
    end
  end

  defp here_api, do: Application.get_env(:edenflowers, :here_api, Edenflowers.External.HereAPI)
end
