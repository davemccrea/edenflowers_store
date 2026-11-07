defmodule Edenflowers.Payments.Validations.Refundable do
  @moduledoc """
  What Jennie can hand back: on something placed or confirmed, cancelled or
  not, with nothing left to collect, up to the money still held, and by
  Stripe only what was paid through it, onto the Gift voucher only what it
  paid, by another method only what was paid in person.

  A Gift voucher sale must be cancelled first, which also stops the voucher,
  so handing its money back can't leave the voucher spendable. Once cancelled,
  money still owed back is refunded by the same rules as any other purchase.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    method = Ash.Changeset.get_argument(changeset, :payment_method)

    case is_struct(amount, Decimal) && check(changeset.data, amount, method) do
      {:error, message} -> {:error, field: :amount, message: message}
      _ok -> :ok
    end
  end

  defp check(record, amount, method) do
    record =
      Ash.load!(
        record,
        [
          :committed?,
          :balance,
          :amount_held,
          :paid_outside_stripe,
          :paid_through_stripe,
          :paid_by_voucher,
          :refund_methods,
          :refunded_only_by_cancelling?
        ],
        authorize?: false,
        reuse_values?: false
      )

    cond do
      record.refunded_only_by_cancelling? ->
        {:error, ~t"Cancel the order to refund a gift voucher. That also stops the voucher."}

      not record.committed? ->
        {:error, ~t"Nothing can be recorded until it's placed or confirmed."}

      Decimal.positive?(record.balance) ->
        {:error, ~t"Collect what's owed before refunding."}

      Decimal.gt?(amount, record.amount_held) ->
        {:error, ~t"That's more than was received."}

      method not in record.refund_methods or Decimal.gt?(amount, held_by(record, method)) ->
        {:error, over_held_by(method)}

      true ->
        :ok
    end
  end

  defp held_by(record, :stripe), do: record.paid_through_stripe
  defp held_by(record, :voucher), do: record.paid_by_voucher
  defp held_by(record, _method), do: record.paid_outside_stripe

  defp over_held_by(:stripe), do: ~t"That's more than was paid through Stripe."
  defp over_held_by(:voucher), do: ~t"That's more than the gift voucher paid."
  defp over_held_by(_method), do: ~t"That's more than was paid outside Stripe. Refund the rest with Stripe."
end
