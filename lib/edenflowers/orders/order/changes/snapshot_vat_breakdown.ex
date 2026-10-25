defmodule Edenflowers.Orders.Order.Changes.SnapshotVatBreakdown do
  @moduledoc """
  Stores the current VAT breakdown on an order when it is placed.
  """

  use Ash.Resource.Change

  alias Edenflowers.Orders.Calculations.Vat

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, Vat.load(nil, nil, nil), authorize?: false)
      Ash.Changeset.force_change_attribute(changeset, :vat_breakdown, Vat.compute_breakdown(order))
    end)
  end
end
