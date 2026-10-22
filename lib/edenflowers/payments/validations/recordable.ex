defmodule Edenflowers.Payments.Validations.Recordable do
  @moduledoc """
  What Jennie can record as a payment's `amount`. Only on something placed
  or confirmed, and never more than is owed: an overpayment isn't a sale.
  Money handed back is a refund (Validations.Refundable).

  With `undo?: true`, for `undo_payment`, the balance doesn't limit it: an
  undo takes back a payment recorded by mistake, whatever is owed.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
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

      Decimal.gt?(amount, record.balance) ->
        error(~t"That's more than is owed.")

      true ->
        :ok
    end
  end

  defp within_paid_outside_stripe(amount, record, message) do
    if Decimal.negative?(amount) and Decimal.negative?(Decimal.add(record.paid_outside_stripe, amount)),
      do: error(message),
      else: :ok
  end

  defp error(message), do: {:error, field: :amount, message: message}
end
