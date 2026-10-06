defmodule Edenflowers.Orders.Changes.CustomOrderFulfillmentFee do
  @moduledoc """
  Prices a custom order's fulfillment as checkout would, unless Jennie has set
  her own fee in `fulfillment_fee_override`. With her own fee she can deliver
  outside the delivery range, so an address that can't be priced only blocks
  the order when there is no override.

  An unchanged delivery address isn't geocoded again: the stored distance is
  enough to price it.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.{DeliveryError, Fee}
  alias Edenflowers.Orders.Changes.ClearDeliveryFields

  @geocoded_fields [:geocoded_address, :position, :here_id, :distance]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &apply_fee/1)
  end

  defp apply_fee(changeset) do
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    case Fulfillment.get_option_by_id(option_id, authorize?: false) do
      {:ok, option} -> apply_fee(changeset, option)
      {:error, _} -> add_error(changeset, :fulfillment_option_id, DeliveryError.message(:unknown))
    end
  end

  defp apply_fee(changeset, %{fulfillment_method: :pickup} = option) do
    %{fulfillment_fee: calculated} = Fee.calculate(option, 0)

    changeset
    |> Ash.Changeset.force_change_attributes(Map.from_keys(ClearDeliveryFields.fields(), nil))
    |> set_fee(calculated)
  end

  defp apply_fee(changeset, option) do
    if needs_geocoding?(changeset) do
      geocode(changeset, option)
    else
      price_stored_distance(changeset, option)
    end
  end

  defp needs_geocoding?(changeset) do
    changeset.action_type == :create or
      Ash.Changeset.changing_attribute?(changeset, :delivery_address) or
      Ash.Changeset.changing_attribute?(changeset, :fulfillment_option_id) or
      is_nil(Ash.Changeset.get_attribute(changeset, :distance))
  end

  defp geocode(changeset, option) do
    address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    case Fulfillment.calculate_delivery(address, option.id, authorize?: false) do
      {:ok, %{error: nil} = result} ->
        changeset
        |> Ash.Changeset.force_change_attributes(Map.take(result, @geocoded_fields))
        |> set_fee(result.fulfillment_fee)

      {:ok, %{error: reason}} ->
        unpriced(changeset, reason)

      {:error, _} ->
        unpriced(changeset, :unknown)
    end
  end

  defp price_stored_distance(changeset, option) do
    case Fee.calculate(option, Ash.Changeset.get_attribute(changeset, :distance)) do
      %{error: nil, fulfillment_fee: calculated} -> set_fee(changeset, calculated)
      %{error: reason} -> unpriced(changeset, reason)
    end
  end

  defp unpriced(changeset, reason) do
    if override(changeset) do
      changeset
      |> Ash.Changeset.force_change_attributes(Map.from_keys(@geocoded_fields, nil))
      |> set_fee(nil)
    else
      add_error(
        changeset,
        :delivery_address,
        ~t"#{reason = DeliveryError.message(reason)}. Enter your own delivery fee to deliver anyway."
      )
    end
  end

  defp set_fee(changeset, calculated) do
    Ash.Changeset.force_change_attribute(changeset, :fulfillment_fee, override(changeset) || calculated)
  end

  defp override(changeset), do: Ash.Changeset.get_attribute(changeset, :fulfillment_fee_override)

  defp add_error(changeset, field, message) do
    Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{field: field, message: message})
  end
end
