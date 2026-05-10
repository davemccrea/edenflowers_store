defmodule Edenflowers.Store.Order.Changes.CopyFulfillmentMethod do
  @moduledoc """
  Denormalizes `fulfillment_method` onto the order whenever
  `fulfillment_option_id` changes, so validations and the UI can read the
  method as a direct attribute instead of traversing the relationship.

  Applied synchronously during the `change` phase (not `before_action`) so
  validations running in the same action see the updated method.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :fulfillment_option_id) do
      set_method(changeset)
    else
      changeset
    end
  end

  defp set_method(changeset) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_option_id) do
      nil ->
        Ash.Changeset.force_change_attribute(changeset, :fulfillment_method, nil)

      id ->
        case Ash.get(FulfillmentOption, id, authorize?: false) do
          {:ok, %{fulfillment_method: method}} ->
            Ash.Changeset.force_change_attribute(changeset, :fulfillment_method, method)

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: :fulfillment_option_id,
              message: "Invalid fulfillment option"
            )
        end
    end
  end
end
