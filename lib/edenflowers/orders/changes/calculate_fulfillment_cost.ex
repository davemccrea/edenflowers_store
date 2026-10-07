defmodule Edenflowers.Orders.Changes.CalculateFulfillmentCost do
  @moduledoc """
  For `submit_delivery`, derives `quoted_fulfillment_fee` (and, for delivery,
  the geocoded fields) from the chosen `FulfillmentOption`. The
  corresponding attributes are not in the action's `accept` list, so this
  change is the only path that can set them — closing the trust-the-client
  gap on delivery cost.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.{DeliveryError, Fee}
  alias Edenflowers.Orders.Changes.ClearDeliveryFields

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &apply_cost/1)
  end

  defp apply_cost(changeset) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_method) do
      :pickup -> apply_pickup(changeset)
      :delivery -> apply_delivery(changeset)
      _ -> changeset
    end
  end

  defp apply_pickup(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    case Fulfillment.get_option_by_id(id, authorize?: false) do
      {:ok, option} ->
        %{fulfillment_fee: fee} = Fee.calculate(option, 0)

        changeset
        |> Ash.Changeset.force_change_attributes(Map.from_keys(ClearDeliveryFields.fields(), nil))
        |> Ash.Changeset.force_change_attribute(:quoted_fulfillment_fee, fee)

      {:error, _} ->
        add_error(changeset, :fulfillment_option_id, :unknown)
    end
  end

  defp apply_delivery(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    case Fulfillment.calculate_delivery(delivery_address, id, authorize?: false) do
      {:ok, %{error: nil} = result} ->
        changeset
        |> Ash.Changeset.force_change_attributes(
          Map.take(result, [:geocoded_address, :position, :here_id, :distance, :in_free_delivery_zone])
        )
        |> Ash.Changeset.force_change_attribute(:quoted_fulfillment_fee, result.fulfillment_fee)

      {:ok, %{error: reason}} ->
        add_error(changeset, :delivery_address, reason)

      {:error, _} ->
        add_error(changeset, :delivery_address, :unknown)
    end
  end

  defp add_error(changeset, field, reason) do
    Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
      field: field,
      message: DeliveryError.message(reason)
    })
  end
end
