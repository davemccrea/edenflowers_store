defmodule Edenflowers.Payments.Changes.Cancel do
  @moduledoc """
  What cancelling means for an order or a course booking. The action sets its
  own status and adds what else is its own, like putting stock back.

  Refuses unless the record is `cancellable?`. Jennie keeps a cancellation
  charge, from 0 up to its Total due, whether or not anything was paid: the
  `cancellation_charge` argument, or else `default_cancellation_charge`. It
  becomes `kept_amount`, and so the Total due, and the Balance follows: what
  was paid above the charge is refunded, and any of the charge not yet paid
  is left as an ordinary purchase balance to collect.

  The refund happens before the cancel commits, so it is never cancelled
  while Stripe still holds money it should have handed back. Card payments
  go back through Stripe first, then what Gift vouchers paid goes back onto
  them; whatever is left was paid in person, and stays as a balance for
  Jennie to hand back. A refund Stripe refuses stops
  the cancel. As the refund is whatever is still held above the charge, a
  retry after Stripe refunded but the cancel failed refunds nothing twice.
  The cancelled email goes to `customer_email`, if there is one, unless the
  `email_customer?` argument is false, as Jennie rewrote it in the `subject`
  and `body` arguments if she did.

  `cancelled_by` (`:customer` or `:shop`) picks who the errors and the email
  speak to, from the option or else the action's `cancelled_by` argument.
  """
  use Ash.Resource.Change

  use GettextSigils,
    backend: EdenflowersWeb.Gettext,
    sigils: [modifiers: [a: [domain: "admin"]]]

  require Ash.Expr
  require Logger

  alias Edenflowers.Email.Edits
  alias Edenflowers.Format
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.CancelOpenPaymentIntent
  alias Edenflowers.Payments.Changes.RecordPayment
  alias Edenflowers.Payments.Payment
  alias Edenflowers.Payments.Workers.SendCancelledEmail

  @impl true
  def change(changeset, opts, context) do
    cancelled_by = opts[:cancelled_by] || Ash.Changeset.get_argument(changeset, :cancelled_by)

    changeset
    |> Ash.Changeset.filter(Ash.Expr.expr(cancellable?))
    |> Ash.Changeset.force_change_attribute(:cancelled_at, DateTime.utc_now())
    |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(Edits.from_changeset(changeset))})
    |> CancelOpenPaymentIntent.change([], context)
    |> Ash.Changeset.before_transaction(&refund(&1, cancelled_by))
    |> Ash.Changeset.after_action(&put_back_on_vouchers/2)
    |> Ash.Changeset.after_action(&queue_email(&1, &2, cancelled_by))
  end

  # Onto the purchase's one Gift voucher. Unlike Stripe's refund, nothing
  # outside can refuse this, so it's in the cancel's own transaction.
  defp put_back_on_vouchers(changeset, record) do
    with %Decimal{} = amount <- changeset.context[:back_on_voucher],
         true <- Decimal.positive?(amount),
         {:ok, _payment} <- record_voucher_refund(record, amount) do
      RecordPayment.reload(record)
    else
      {:error, _error} = error -> error
      _nothing_back -> {:ok, record}
    end
  end

  defp record_voucher_refund(record, amount) do
    Payment
    |> Ash.Changeset.for_create(:record, %{
      Payments.parent_key(record) => record.id,
      amount: Decimal.negate(amount),
      method: :voucher,
      gift_voucher_id: record.gift_voucher_id
    })
    |> Ash.create(authorize?: false)
  end

  defp refund(changeset, cancelled_by) do
    record =
      Ash.load!(
        changeset.data,
        load(),
        authorize?: false,
        reuse_values?: false
      )

    with true <- record.cancellable? || {:error, changed_message(cancelled_by)},
         {:ok, charge} <- charge(changeset, record) do
      money = money(record, charge)

      changeset
      |> Ash.Changeset.force_change_attribute(:kept_amount, charge)
      |> Ash.Changeset.set_context(money)
      |> set_email(record.customer_email)
      |> refund_through_stripe(record, charge, money.refunded, cancelled_by)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  @doc "What `money/2` and cancelling need loaded."
  def load,
    do: [
      :cancellable?,
      :total_due,
      :amount_held,
      :amount_paid,
      :paid_through_stripe,
      :paid_by_voucher,
      :default_cancellation_charge,
      :customer_email
    ]

  @doc """
  What keeping `charge` on cancelling means for the money: what goes back
  through Stripe (`refunded`), what goes back onto the Gift vouchers that
  paid (`back_on_voucher`), what Jennie hands back herself (`to_return`) and
  what of the charge is still to collect (`to_collect`). Paid above the
  charge is refunded, the card's first; a Goodwill refund already given
  counts as paid, as it does for the Balance.

  """
  def money(record, charge) do
    to_refund = Decimal.max(Decimal.sub(record.amount_held, charge), 0)
    refunded = Decimal.min(to_refund, Decimal.max(record.paid_through_stripe, 0))
    after_stripe = Decimal.sub(to_refund, refunded)
    back_on_voucher = Decimal.min(after_stripe, Decimal.max(record.paid_by_voucher, 0))
    to_collect = Decimal.max(Decimal.sub(charge, record.amount_paid), 0)

    %{
      charge: charge,
      refunded: refunded,
      back_on_voucher: back_on_voucher,
      to_return: Decimal.sub(after_stripe, back_on_voucher),
      to_collect: to_collect
    }
  end

  defp charge(changeset, record) do
    total = Decimal.max(record.total_due, 0)

    case Ash.Changeset.get_argument(changeset, :cancellation_charge) do
      nil ->
        {:ok, record.default_cancellation_charge}

      charge ->
        if Decimal.negative?(charge) or Decimal.gt?(charge, total),
          do:
            {:error,
             field: :cancellation_charge,
             message: ~t"Enter an amount from 0 € to #{amount = Format.currency(total, Format.locale())}."a},
          else: {:ok, charge}
    end
  end

  defp set_email(changeset, email) do
    if email && Ash.Changeset.get_argument(changeset, :email_customer?) != false,
      do: Ash.Changeset.force_change_attribute(changeset, :cancellation_emailed_to, email),
      else: changeset
  end

  defp refund_through_stripe(changeset, record, kept, refunded, cancelled_by) do
    if Decimal.eq?(refunded, 0) do
      changeset
    else
      case Payments.refund_all_but_kept(record, kept) do
        {:ok, _refunds} ->
          changeset

        {:error, error} ->
          Logger.error("Could not refund #{inspect(record.__struct__)} #{record.id} on cancelling: #{inspect(error)}")
          Ash.Changeset.add_error(changeset, refused_message(cancelled_by))
      end
    end
  end

  defp queue_email(changeset, record, cancelled_by) do
    if Ash.Changeset.changing_attribute?(changeset, :cancellation_emailed_to) do
      job = SendCancelledEmail.new_for(record, changeset.context, cancelled_by, Edits.from_changeset(changeset))

      with {:ok, _job} <- Oban.insert(job) do
        {:ok, record}
      end
    else
      {:ok, record}
    end
  end

  defp changed_message(:customer), do: ~t"This order can no longer be cancelled online. Please contact us."
  defp changed_message(:shop), do: ~t"This changed while you had it open, so it wasn't cancelled."a

  defp refused_message(:customer), do: ~t"We couldn't refund your order. Please contact us to cancel it."

  defp refused_message(:shop),
    do: ~t"Stripe refused the refund, so nothing was cancelled. Check the payment in Stripe."a
end
