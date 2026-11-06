defmodule Edenflowers.Orders.Order.Changes.IssueGiftVouchers do
  @moduledoc """
  Issues the Gift voucher a placed sale's voucher line sold, at its amount.
  The voucher is handed over in the receipt email, so the order is fulfilled
  as it's placed, unless the buyer collects a gift card at the shop, which
  Jennie writes the voucher onto: then it stays open until Jennie marks it
  collected.

  A sale Jennie enters in the shop is created with its line, which exists only
  once the order is saved, and is handed over as she writes the card, so its
  action fulfils it.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments

  @impl true
  def change(%{action_type: :create} = changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      issue(Ash.load!(order, :gift_voucher_line, authorize?: false).gift_voucher_line)
      {:ok, order}
    end)
  end

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.load!(changeset.data, :gift_voucher_line, authorize?: false).gift_voucher_line do
        nil -> changeset
        line -> fulfil_and_issue(changeset, line)
      end
    end)
  end

  defp fulfil_and_issue(changeset, line) do
    changeset =
      if changeset.data.collect_voucher_card,
        do: changeset,
        else: Ash.Changeset.force_change_attribute(changeset, :fulfillment_status, :fulfilled)

    # ponytail: issued at the line's amount, not what Stripe took, so a sale revised while its payment was
    # in flight issues more than was paid (ReportAmountMismatch logs it). Fix: min(unit_price, amount_paid).
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      issue(line)
      {:ok, order}
    end)
  end

  defp issue(line),
    do: Payments.create_gift_voucher!(%{amount: line.unit_price, line_item_id: line.id}, authorize?: false)
end
