defmodule Edenflowers.Store.Order.Changes.CalculateFulfillmentCost do
  @moduledoc """
  For `save_step_3`, derives `fulfillment_amount` (and, for delivery, the
  geocoded fields) from the chosen `FulfillmentOption`. The corresponding
  attributes are not in the action's `accept` list, so this change is the
  only path that can set them — closing the trust-the-client gap on
  delivery cost.

  Reuses the option stashed in the changeset context by
  `CopyFulfillmentMethod` when present; otherwise fetches directly. A
  single submit performs at most one `Ash.get/2` for the option.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.FulfillmentOption

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
    with {:ok, option} <- get_option(changeset),
         {:ok, amount} <- Fulfillments.calculate_price(option) do
      Ash.Changeset.force_change_attributes(changeset,
        fulfillment_amount: amount,
        delivery_address: nil,
        delivery_instructions: nil,
        geocoded_address: nil,
        position: nil,
        here_id: nil,
        distance: nil
      )
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :fulfillment_option_id,
          message: Fulfillments.delivery_error_message(:unknown)
        })
    end
  end

  defp apply_delivery(changeset) do
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    with {:ok, option} <- get_option(changeset),
         {:ok, result} <- Fulfillments.calculate_delivery(delivery_address, option) do
      Ash.Changeset.force_change_attributes(changeset,
        geocoded_address: result.geocoded_address,
        position: result.position,
        here_id: result.here_id,
        distance: result.distance,
        fulfillment_amount: result.fulfillment_amount
      )
    else
      {:error, reason} when is_atom(reason) ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: Fulfillments.delivery_error_message(reason)
        })

      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: Fulfillments.delivery_error_message(:unknown)
        })
    end
  end

  defp get_option(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    case changeset.context[:fulfillment_option] do
      %{id: ^id} = option -> {:ok, option}
      _ -> Ash.get(FulfillmentOption, id, authorize?: false)
    end
  end
end
