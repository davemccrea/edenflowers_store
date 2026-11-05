defmodule Edenflowers.Payments.Changes.Refund do
  @moduledoc """
  Hands back `amount`. Through Stripe, before the change commits, and
  `Payments.record_stripe_refund/1` records it. Onto a Gift voucher, or by
  any other method Jennie already handed it back by: its negative goes in
  `refund` for `SplitOffGoodwill` to split and `RecordPayment` to record.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

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

      # A purchase is paid by one Gift voucher at most: the one it holds.
      :voucher ->
        changeset
        |> Ash.Changeset.set_argument(:refund, Decimal.negate(amount))
        |> Ash.Changeset.set_argument(:gift_voucher_id, changeset.data.gift_voucher_id)

      _handed_back ->
        Ash.Changeset.set_argument(changeset, :refund, Decimal.negate(amount))
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
end
