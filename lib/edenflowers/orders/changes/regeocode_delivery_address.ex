defmodule Edenflowers.Orders.Changes.RegeocodeDeliveryAddress do
  @moduledoc """
  Finds a corrected delivery address on the map without repricing it: the
  customer has paid the fee already. If the address can't be found, the map
  falls back to the typed address.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment

  @geocoded_fields [:geocoded_address, :position, :here_id, :distance]

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :delivery_address) and
         Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery do
      Ash.Changeset.before_action(changeset, &regeocode/1)
    else
      changeset
    end
  end

  defp regeocode(changeset) do
    address = Ash.Changeset.get_attribute(changeset, :delivery_address)
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    geocoded =
      case Fulfillment.calculate_delivery(address, option_id, authorize?: false) do
        {:ok, %{error: nil} = result} -> Map.take(result, @geocoded_fields)
        _ -> Map.from_keys(@geocoded_fields, nil)
      end

    Ash.Changeset.force_change_attributes(changeset, geocoded)
  end
end
