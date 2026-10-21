defmodule Edenflowers.Payments.Validations.Recordable do
  @moduledoc """
  What Jennie can record as an `amount`. Only on something placed or
  confirmed, and never taking the balance past zero: an overpayment isn't a
  sale, and money handed back on something that still stands is a goodwill
  refund (Validations.GoodwillRefundable). A refund can't be larger than the
  money paid outside Stripe, which goes back through Stripe.

  With `undo?: true`, for `undo_payment`, the balance doesn't limit it: an
  undo takes back a payment recorded by mistake, whatever is owed.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)

    record =
      Ash.load!(changeset.data, [:committed?, :balance, :paid_outside_stripe],
        authorize?: false,
        reuse_values?: false
      )

    cond do
      not record.committed? ->
        error(~t"Nothing can be recorded until it's placed or confirmed.")

      not is_struct(amount, Decimal) ->
        :ok

      opts[:undo?] ->
        within_paid_outside_stripe(amount, record, ~t"Its money was since refunded. Undo the refund first.")

      Decimal.positive?(amount) and Decimal.gt?(amount, record.balance) ->
        error(~t"That's more than is owed.")

      Decimal.negative?(amount) and not Decimal.negative?(record.balance) ->
        error(~t"Nothing is owed back. Lower the price or cancel before refunding.")

      Decimal.negative?(amount) and Decimal.lt?(amount, record.balance) ->
        error(~t"That's more than is owed back.")

      true ->
        within_paid_outside_stripe(
          amount,
          record,
          ~t"That's more than was paid outside Stripe. Refund the rest with Stripe."
        )
    end
  end

  defp within_paid_outside_stripe(amount, record, message) do
    if Decimal.negative?(amount) and Decimal.negative?(Decimal.add(record.paid_outside_stripe, amount)),
      do: error(message),
      else: :ok
  end

  defp error(message), do: {:error, field: :amount, message: message}
end
