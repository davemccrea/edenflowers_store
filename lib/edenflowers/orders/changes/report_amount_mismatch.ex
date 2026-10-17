defmodule Edenflowers.Orders.Changes.ReportAmountMismatch do
  @moduledoc """
  The customer has paid, so the order is placed even when Stripe received a
  different amount, usually because the cart changed while payment was in
  flight. Logged as an error so it reaches ErrorTracker; the admin orders list
  also flags it, as an amount to collect or refund.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      checked = Ash.load!(order, [:grand_total, :amount_paid], authorize?: false, reuse_values?: false)

      if not Decimal.eq?(checked.amount_paid, checked.grand_total) do
        Logger.error(
          "Amount mismatch for order #{order.id} (expected: #{checked.grand_total}, got: #{checked.amount_paid}). " <>
            "Placed it anyway; the cart likely changed while payment was in flight."
        )
      end

      {:ok, order}
    end)
  end
end
