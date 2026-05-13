defmodule Edenflowers.Store.Order.Changes.CopyFulfillmentMethod do
  @moduledoc """
  Denormalizes `fulfillment_method` and `fulfillment_tax_rate` onto the
  order whenever `fulfillment_option_id` changes. The method makes
  validations and templates branch on a plain attribute; the tax rate
  snapshot lets the live `fulfillment_tax_amount` calculation — and the
  placed snapshot — survive a later edit to the upstream tax rate.

  Applied synchronously during the `change` phase (not `before_action`) so
  validations running in the same action see the updated method.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :fulfillment_option_id) do
      set_from_option(changeset)
    else
      changeset
    end
  end

  defp set_from_option(changeset) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_option_id) do
      nil ->
        Ash.Changeset.force_change_attributes(changeset,
          fulfillment_method: nil,
          fulfillment_tax_rate: nil
        )

      id ->
        case Ash.get(FulfillmentOption, id, load: [:tax_rate], authorize?: false) do
          {:ok, %{fulfillment_method: method, tax_rate: %{percentage: percentage}}} ->
            Ash.Changeset.force_change_attributes(changeset,
              fulfillment_method: method,
              fulfillment_tax_rate: percentage
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
