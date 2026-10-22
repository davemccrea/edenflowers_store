defmodule Edenflowers.Payments.Changes.Refund do
  @moduledoc """
  Hands back `amount`. Through Stripe, before the change commits, and
  `Payments.record_stripe_refund/1` records it. By any other method, Jennie
  already handed it back: it's split into what was owed back (`owed_back`)
  and the rest (`goodwill_refund`) for `RecordPayment` to record.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger

  alias Edenflowers.Payments

  @impl true
  def change(%{valid?: false} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    amount = Ash.Changeset.get_argument(changeset, :amount)
    note = Ash.Changeset.get_argument(changeset, :note)

    case Ash.Changeset.get_argument(changeset, :payment_method) do
      :stripe ->
        Ash.Changeset.before_transaction(changeset, &refund_with_stripe(&1, amount, note))

      _handed_back ->
        record = Ash.load!(changeset.data, :balance, authorize?: false, reuse_values?: false)
        owed_back = Decimal.min(amount, Decimal.max(Decimal.negate(record.balance), 0))

        changeset
        |> set_unless_zero(:owed_back, Decimal.negate(owed_back))
        |> set_unless_zero(:goodwill_refund, Decimal.negate(Decimal.sub(amount, owed_back)))
    end
  end

  defp refund_with_stripe(changeset, amount, note) do
    case Payments.refund_amount(changeset.data, amount, note) do
      {:ok, _refunds} ->
        changeset

      {:error, error} ->
        record = changeset.data
        Logger.error("Stripe refund for #{inspect(record.__struct__)} #{record.id} failed: #{inspect(error)}")
        Ash.Changeset.add_error(changeset, ~t"Could not refund with Stripe. Check the payment in Stripe.")
    end
  end

  defp set_unless_zero(changeset, argument, amount) do
    if Decimal.eq?(amount, 0), do: changeset, else: Ash.Changeset.set_argument(changeset, argument, amount)
  end
end
