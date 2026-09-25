defmodule Edenflowers.Orders.Order.Changes.EnsureEditable do
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order =
        Order
        |> Ash.Query.filter(id == ^changeset.data.id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!(authorize?: false)

      if order.state in Order.checkout_states() do
        changeset
      else
        Ash.Changeset.add_error(changeset, "order is not editable")
      end
    end)
  end
end
