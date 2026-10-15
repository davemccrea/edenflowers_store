defmodule Edenflowers.Payments.Changes.RefundInFull do
  @moduledoc """
  Refunds everything the customer paid before the change commits, so an order
  is never cancelled while still holding their money. A refund Stripe refuses
  stops the change.

  Puts what was paid in the `:refunded_amount` context for the email that
  tells the customer.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Payments

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      order = Ash.load!(changeset.data, :amount_paid, authorize?: false, reuse_values?: false)

      case Payments.refund_in_full(order) do
        {:ok, _refunds} ->
          Ash.Changeset.set_context(changeset, %{refunded_amount: order.amount_paid || Decimal.new(0)})

        {:error, error} ->
          Logger.error("Could not refund order #{order.id} the customer cancelled: #{inspect(error)}")
          Ash.Changeset.add_error(changeset, ~t"We couldn't refund your order. Please contact us to cancel it.")
      end
    end)
  end
end
