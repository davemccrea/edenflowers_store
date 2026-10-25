defmodule Edenflowers.Orders.Order.Changes.PriceFulfillment do
  @moduledoc """
  Prices fulfillment on an order Jennie places or edits, as checkout would,
  unless she has set her own fee in `fulfillment_fee_override`. With her own
  fee she can deliver outside the delivery range, so an address that can't be
  priced only blocks the order when there is no override.

  An edit that leaves the method, address and override alone keeps the fee the
  order already has, even if the option's prices have changed since.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.DeliveryError
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders.Order.Changes.ClearDeliveryFields

  @geocoded_fields [:geocoded_address, :position, :here_id, :distance]

  @priced_by [:fulfillment_option_id, :delivery_address, :fulfillment_fee_override]

  @impl true
  def change(changeset, _opts, _context) do
    if reprices?(changeset) do
      Ash.Changeset.before_action(changeset, &apply_fee/1)
    else
      changeset
    end
  end

  @doc "Whether saving `changeset` prices fulfillment afresh, rather than keeping the order's fee."
  def reprices?(changeset) do
    changeset.action_type == :create or Enum.any?(@priced_by, &Ash.Changeset.changing_attribute?(changeset, &1))
  end

  @doc """
  What saving `changeset` sets to price its fulfillment, as `{:ok, attributes}`,
  or `{:error, field, message}` when it can't be priced. `locate` prices an
  address for a delivery option the way `Fulfillment.calculate_delivery/3`
  does, as `{:ok, result}` or `{:error, reason}`, so the quote can price with
  the lookup the form already made.
  """
  def price(changeset, locate) do
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    case option_id && Fulfillment.get_option_by_id(option_id, authorize?: false) do
      {:ok, option} -> price(changeset, option, locate)
      _ -> {:error, :fulfillment_option_id, DeliveryError.message(:unknown)}
    end
  end

  defp price(changeset, %{fulfillment_method: :pickup} = option, _locate) do
    {:ok, Map.merge(Map.from_keys(ClearDeliveryFields.fields(), nil), fee(changeset, Fee.calculate(option, 0)))}
  end

  # Only a new override reuses the stored distance; a new address or option is located.
  defp price(changeset, option, locate) do
    if needs_geocoding?(changeset) do
      located(changeset, locate.(Ash.Changeset.get_attribute(changeset, :delivery_address), option))
    else
      price_stored_distance(changeset, option)
    end
  end

  defp apply_fee(changeset) do
    case price(changeset, &geocode/2) do
      {:ok, attributes} -> Ash.Changeset.force_change_attributes(changeset, attributes)
      {:error, field, message} -> add_error(changeset, field, message)
    end
  end

  defp geocode(address, option) do
    case Fulfillment.calculate_delivery(address, option.id, authorize?: false) do
      {:ok, %{error: nil} = result} -> {:ok, result}
      {:ok, %{error: reason}} -> {:error, reason}
      {:error, _} -> {:error, :unknown}
    end
  end

  defp needs_geocoding?(changeset) do
    changeset.action_type == :create or
      Ash.Changeset.changing_attribute?(changeset, :delivery_address) or
      Ash.Changeset.changing_attribute?(changeset, :fulfillment_option_id) or
      is_nil(Ash.Changeset.get_attribute(changeset, :distance))
  end

  defp located(changeset, {:ok, result}),
    do: {:ok, Map.merge(Map.take(result, @geocoded_fields), fee(changeset, result))}

  defp located(changeset, {:error, reason}), do: unpriced(changeset, reason)

  defp price_stored_distance(changeset, option) do
    case Fee.calculate(option, Ash.Changeset.get_attribute(changeset, :distance)) do
      %{error: nil} = calculated -> {:ok, fee(changeset, calculated)}
      %{error: reason} -> unpriced(changeset, reason)
    end
  end

  # With her own fee Jennie can deliver to an address that can't be priced.
  defp unpriced(changeset, reason) do
    if override(changeset) do
      {:ok,
       Map.merge(
         Map.from_keys(@geocoded_fields, nil),
         fee(changeset, %{fulfillment_fee: nil, in_free_delivery_zone: false})
       )}
    else
      {:error, :delivery_address,
       ~t"#{reason = DeliveryError.message(reason)}. Enter your own delivery fee to deliver anyway."}
    end
  end

  # Jennie's own fee wins over the calculated one.
  defp fee(changeset, %{fulfillment_fee: calculated, in_free_delivery_zone: in_zone}) do
    %{quoted_fulfillment_fee: override(changeset) || calculated, in_free_delivery_zone: in_zone}
  end

  defp override(changeset), do: Ash.Changeset.get_attribute(changeset, :fulfillment_fee_override)

  defp add_error(changeset, field, message) do
    Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{field: field, message: message})
  end
end
