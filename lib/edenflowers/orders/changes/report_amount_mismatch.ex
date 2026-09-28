defmodule Edenflowers.Orders.Changes.ReportAmountMismatch do
  @moduledoc """
  The customer has paid, so the order is placed even when Stripe received a
  different amount, usually because the cart changed while payment was in
  flight. Logged as an error so it reaches ErrorTracker; the admin orders list
  also flags it via `amount_mismatch?`.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      checked = Ash.load!(order, [:amount_mismatch?, :grand_total], authorize?: false)

      if checked.amount_mismatch? do
        Logger.error(
          "Amount mismatch for order #{order.id} (expected: #{checked.grand_total}, got: #{order.amount_paid}). " <>
            "Placed it anyway; the cart likely changed while payment was in flight."
        )
      end

      {:ok, order}
    end)
  end
end
