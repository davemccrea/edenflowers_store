defmodule Edenflowers.Store.Order.ValidateFulfillmentDate do
  @moduledoc """
  Validates that the fulfillment_date is provided and not in the past.

  This ensures:
  1. fulfillment_date is not nil
  2. fulfillment_date is today or in the future
  """
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    fulfillment_date = Ash.Changeset.get_attribute(changeset, :fulfillment_date)

    cond do
      is_nil(fulfillment_date) ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{
          field: :fulfillment_date,
          type: :attribute
        })

      Date.compare(fulfillment_date, Date.utc_today()) == :lt ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :fulfillment_date,
          message: gettext("Fulfillment date cannot be in the past")
        })

      true ->
        changeset
    end
  end
end
