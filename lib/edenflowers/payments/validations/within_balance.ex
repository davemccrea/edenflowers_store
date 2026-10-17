defmodule Edenflowers.Payments.Validations.WithinBalance do
  @moduledoc """
  Refuses an `amount` Jennie records that would take the balance past zero.
  An overpayment isn't a sale, and a goodwill refund on something that still
  stands has to lower it first, so the monthly report sees a lower sale.

  A refund while something is still to collect corrects a payment recorded by
  mistake, which only moves the balance further from zero.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    %{balance: balance} = Ash.load!(changeset.data, :balance, authorize?: false, reuse_values?: false)

    cond do
      not is_struct(amount, Decimal) ->
        :ok

      Decimal.positive?(amount) and Decimal.gt?(amount, balance) ->
        {:error, field: :amount, message: "That's more than is owed"}

      Decimal.negative?(amount) and Decimal.eq?(balance, 0) ->
        {:error, field: :amount, message: "Lower the order or cancel it before refunding"}

      Decimal.negative?(amount) and Decimal.negative?(balance) and Decimal.lt?(amount, balance) ->
        {:error, field: :amount, message: "That's more than is owed back"}

      true ->
        :ok
    end
  end
end
