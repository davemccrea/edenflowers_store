defmodule Edenflowers.Store.Order.Changes.CalculateDeliveryCost do
  @moduledoc """
  For delivery orders, derives `geocoded_address`, `position`, `here_id`,
  `distance`, and `fulfillment_amount` server-side from the user-typed
  `delivery_address` by calling `Edenflowers.Fulfillments.calculate_delivery/2`.
  This is the trust boundary: client-supplied values for these attributes
  are not accepted on `save_step_3`, so the cost can only be set by this
  change.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.Order.Changes.FulfillmentOptionCache

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery do
        apply_cost(changeset)
      else
        changeset
      end
    end)
  end

  defp apply_cost(changeset) do
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    with {:ok, option, changeset} <- FulfillmentOptionCache.fetch(changeset, id),
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

      {:error, _} ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: Fulfillments.delivery_error_message(:unknown)
        })
    end
  end
end
