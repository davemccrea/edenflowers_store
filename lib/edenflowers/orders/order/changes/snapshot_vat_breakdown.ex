defmodule Edenflowers.Orders.Order.Changes.SnapshotVatBreakdown do
  use Ash.Resource.Change

  alias Edenflowers.Orders.Order.Calculations.Vat

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, Vat.load(nil, nil, nil), authorize?: false)
      Ash.Changeset.force_change_attribute(changeset, :vat_breakdown, Vat.breakdown(order))
    end)
  end
end
