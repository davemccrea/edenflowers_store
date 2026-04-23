defmodule Edenflowers.Store.Order.Changes.CalculatePickupCost do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :pickup do
        apply_price(changeset)
      else
        changeset
      end
    end)
  end

  defp apply_price(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    with {:ok, option} <- Ash.get(FulfillmentOption, id, authorize?: false),
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
          message: ~t"Unable to calculate fulfillment cost"
        })
    end
  end
end
