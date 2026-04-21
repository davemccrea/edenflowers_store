defmodule Edenflowers.Store.Order.Changes.GenerateOrderReference do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    reference = :crypto.strong_rand_bytes(4) |> Base.encode16()
    Ash.Changeset.force_change_attribute(changeset, :order_reference, reference)
  end
end
