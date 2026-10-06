defmodule Edenflowers.Orders.Changes.ReportUnexpectedPayment do
  @moduledoc """
  The money has arrived, so it is recorded however it came about. When the
  order was cancelled, or is now overpaid because the customer also paid in
  person, Jennie has to refund the difference. Logged as an error so it
  reaches ErrorTracker; the order page shows the balance to refund.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      checked = Ash.load!(order, [:balance], authorize?: false, reuse_values?: false)

      cond do
        order.fulfillment_status == :cancelled ->
          Logger.error("Order #{order.id} was paid online after it was cancelled. Refund it in Stripe.")

        Decimal.negative?(checked.balance) ->
          Logger.error(
            "Order #{order.id} is overpaid by #{Decimal.abs(checked.balance)} after a payment link payment. " <>
              "Refund the difference in Stripe."
          )

        true ->
          :ok
      end

      {:ok, order}
    end)
  end
end
