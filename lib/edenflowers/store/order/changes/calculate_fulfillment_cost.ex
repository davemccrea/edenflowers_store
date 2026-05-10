defmodule Edenflowers.Store.Order.Changes.CalculateFulfillmentCost do
  @moduledoc """
  For `submit_delivery`, derives `fulfillment_amount` (and, for delivery,
  the geocoded fields) and captures `fulfillment_tax_rate` from the
  chosen `FulfillmentOption`. These attributes are not in the action's
  `accept` list, so this change is the only path that can set them.
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
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    with {:ok, option} <- load_option(id),
         {:ok, amount} <- Fulfillments.calculate_price(option) do
      Ash.Changeset.force_change_attributes(changeset,
        fulfillment_amount: amount,
        fulfillment_tax_rate: option.tax_rate.percentage,
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
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    with {:ok, option} <- load_option(id),
         {:ok, result} <- Fulfillments.calculate_delivery(delivery_address, option) do
      Ash.Changeset.force_change_attributes(changeset,
        geocoded_address: result.geocoded_address,
        position: result.position,
        here_id: result.here_id,
        distance: result.distance,
        fulfillment_amount: result.fulfillment_amount,
        fulfillment_tax_rate: option.tax_rate.percentage
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

  defp load_option(nil), do: {:error, :missing_option}

  defp load_option(id) do
    case Ash.get(FulfillmentOption, id, load: [:tax_rate], authorize?: false) do
      {:ok, %{tax_rate: %{percentage: _}} = option} -> {:ok, option}
      {:ok, _} -> {:error, :missing_tax_rate}
      {:error, error} -> {:error, error}
    end
  end
end
