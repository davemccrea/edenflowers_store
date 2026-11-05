defmodule Edenflowers.Orders.Order.Changes.IssueGiftVouchers do
  @moduledoc """
  Issues the Gift voucher a placed sale's voucher line sold, at its amount.
  The voucher is handed over in the receipt email, so the order is fulfilled
  as it's placed, unless the buyer collects a gift card at the shop, which
  Jennie writes the voucher onto: then it stays open until Jennie marks it
  collected.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.load!(changeset.data, :gift_voucher_line, authorize?: false).gift_voucher_line do
        nil -> changeset
        line -> issue(changeset, line)
      end
    end)
  end

  defp issue(changeset, line) do
    changeset =
      if changeset.data.collect_voucher_card,
        do: changeset,
        else: Ash.Changeset.force_change_attribute(changeset, :fulfillment_status, :fulfilled)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      Payments.create_gift_voucher!(%{amount: line.unit_price, line_item_id: line.id}, authorize?: false)
      {:ok, order}
    end)
  end
end
