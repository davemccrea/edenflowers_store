defmodule Edenflowers.Orders.Order.Changes.SnapshotFulfillmentMethod do
  @moduledoc """
  Mirrors selected fields from the chosen `FulfillmentOption` onto the order.
  The order's :placed policy then freezes them as the commercial record,
  independent of later edits to the option or its `TaxRate`.

  Runs in the `change` phase (not `before_action`) so validations in the
  same action see the updated method.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :fulfillment_option_id) do
      snapshot(changeset)
    else
      changeset
    end
  end

  defp snapshot(changeset) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_option_id) do
      nil ->
        Ash.Changeset.force_change_attributes(changeset,
          fulfillment_method: nil,
          fulfillment_tax_percentage: nil,
          fulfillment_option_name: nil
        )

      id ->
        case Ash.get(FulfillmentOption, id, load: [:tax_rate], authorize?: false) do
          {:ok, %{fulfillment_method: method, name: name, tax_rate: %{percentage: percentage}}} ->
            Ash.Changeset.force_change_attributes(changeset,
              fulfillment_method: method,
              fulfillment_tax_percentage: percentage,
              fulfillment_option_name: name
            )

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: :fulfillment_option_id,
              message: "Invalid fulfillment option"
            )
        end
    end
  end
end
