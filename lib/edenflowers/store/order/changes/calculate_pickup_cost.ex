defmodule Edenflowers.Store.Order.CalculatePickupCost do
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

      case Ash.get(Edenflowers.Store.FulfillmentOption, fulfillment_option_id, authorize?: false) do
        {:ok, %{fulfillment_method: :pickup} = fulfillment_option} ->
          case Fulfillments.calculate_price(fulfillment_option) do
            {:ok, fulfillment_amount} ->
              Ash.Changeset.force_change_attributes(changeset,
                fulfillment_amount: fulfillment_amount,
                delivery_address: nil,
                delivery_instructions: nil,
                geocoded_address: nil,
                position: nil,
                here_id: nil,
                distance: nil
              )

            {:error, _reason} ->
              Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
                field: :fulfillment_option_id,
                message: ~t"Unable to calculate fulfillment cost"
              })
          end

        _ ->
          changeset
      end
    end)
  end
end
