defmodule Edenflowers.Payments.Validations.GoodwillRefundable do
  @moduledoc """
  What Jennie can hand back as a goodwill refund: on something placed or
  confirmed with nothing left to collect, or cancelled with nothing owed back, up to the money
  still held, and by Stripe only what was paid through it, by another method
  only what was paid outside it.

  `check/3` is the same rule for `Payments.refund_goodwill/3`, which refunds
  through Stripe outside an action.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    method = Ash.Changeset.get_argument(changeset, :payment_method)

    case is_struct(amount, Decimal) && check(changeset.data, amount, method) do
      {:error, message} -> {:error, field: :amount, message: message}
      _ok -> :ok
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def check(record, amount, method) do
    record =
      Ash.load!(
        record,
        [:committed?, :cancelled?, :balance, :amount_held, :paid_outside_stripe, :paid_through_stripe],
        authorize?: false,
        reuse_values?: false
      )

    cond do
      not record.committed? ->
        {:error, ~t"Nothing can be recorded until it's placed or confirmed."}

      Decimal.positive?(record.balance) ->
        {:error, ~t"Collect what's owed before refunding."}

      record.cancelled? and Decimal.negative?(record.balance) ->
        {:error, ~t"It's cancelled, so refund what's owed back instead."}

      Decimal.gt?(amount, record.amount_held) ->
        {:error, ~t"That's more than was received."}

      method == :stripe and Decimal.gt?(amount, record.paid_through_stripe) ->
        {:error, ~t"That's more than was paid through Stripe."}

      method != :stripe and Decimal.gt?(amount, record.paid_outside_stripe) ->
        {:error, ~t"That's more than was paid outside Stripe. Refund the rest with Stripe."}

      true ->
        :ok
    end
  end
end
