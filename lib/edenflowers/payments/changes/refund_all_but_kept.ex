defmodule Edenflowers.Payments.Changes.RefundAllButKept do
  @moduledoc """
  Refunds what the customer paid, apart from `kept_amount`, before the cancel
  commits, so it is never cancelled while Stripe still holds money it should
  have handed back. A refund Stripe refuses stops the change.

  Card payments go back through Stripe first; whatever is left was paid in
  person, and stays as a balance for Jennie to hand back. Both amounts go in
  the `:refunded` and `:to_return` context for the email that tells the
  customer.

  `cancelled_by` picks who the error speaks to: `:customer` or `:shop`.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Payments

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      record =
        Ash.load!(changeset.data, [:amount_held, :paid_through_stripe], authorize?: false, reuse_values?: false)

      kept = Ash.Changeset.get_attribute(changeset, :kept_amount)
      to_refund = Decimal.max(Decimal.sub(record.amount_held, kept), 0)
      refunded = Decimal.min(to_refund, Decimal.max(record.paid_through_stripe, 0))
      context = %{refunded: refunded, to_return: Decimal.sub(to_refund, refunded)}

      cond do
        Decimal.gt?(kept, Decimal.max(record.amount_held, 0)) ->
          Ash.Changeset.add_error(changeset, field: :kept_amount, message: ~t"That's more than was paid.")

        Decimal.eq?(refunded, 0) ->
          Ash.Changeset.set_context(changeset, context)

        true ->
          case Payments.refund_all_but_kept(record, kept) do
            {:ok, _refunds} ->
              Ash.Changeset.set_context(changeset, context)

            {:error, error} ->
              Logger.error(
                "Could not refund #{inspect(record.__struct__)} #{record.id} on cancelling: #{inspect(error)}"
              )

              Ash.Changeset.add_error(changeset, refused_message(opts[:cancelled_by]))
          end
      end
    end)
  end

  defp refused_message(:customer), do: ~t"We couldn't refund your order. Please contact us to cancel it."
  defp refused_message(:shop), do: ~t"Stripe refused the refund, so nothing was cancelled. Check the payment in Stripe."
end
