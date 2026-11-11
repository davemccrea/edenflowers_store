defmodule Edenflowers.Orders.Order.Changes.SnapshotVatBreakdown do
  @moduledoc """
  Stores the current VAT breakdown and grand total on an order when it is
  placed, and again whenever Jennie changes its lines or fees.
  """

  use Ash.Resource.Change

  alias Edenflowers.Orders.Calculations.Vat

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, [:grand_total | Vat.load(nil, nil, nil)], authorize?: false)

      # From grand_total, not the breakdown: the breakdown leaves out Gift voucher lines.
      Ash.Changeset.force_change_attributes(changeset,
        vat_breakdown: Vat.compute_breakdown(order),
        stored_grand_total: order.grand_total
      )
    end)
  end
end
