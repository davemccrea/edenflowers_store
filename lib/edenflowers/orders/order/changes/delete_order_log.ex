defmodule Edenflowers.Orders.Order.Changes.DeleteOrderLog do
  @moduledoc """
  Deletes an order's log before the order itself, which the log references.
  The log has no destroy action, as nothing else may remove its entries.
  """
  use Ash.Resource.Change

  import Ecto.Query

  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      Edenflowers.Repo.delete_all(from(v in Order.Version, where: v.version_source_id == ^changeset.data.id))
      changeset
    end)
  end
end
