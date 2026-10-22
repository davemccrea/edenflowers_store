defmodule Edenflowers.Payments.Changes.Cancel do
  @moduledoc """
  What cancelling means for an order or a course booking. The action sets its
  own status and adds what else is its own, like putting stock back.

  Refuses unless the record is `cancellable?`, then refunds everything held
  apart from what Jennie keeps, before the cancel commits, so it is never
  cancelled while Stripe still holds money it should have handed back. Card
  payments go back through Stripe first; whatever is left was paid in person,
  and stays as a balance for Jennie to hand back. A refund Stripe refuses
  stops the cancel. The cancelled email goes to `customer_email`, if there is
  one, unless the `email_customer?` argument is false.

  What's kept comes from two optional arguments: `refund`, what Jennie typed,
  and `held`, what was held when she opened the drawer. Kept is `held` minus
  `refund`, so a retry after Stripe refunded but the cancel failed keeps the
  same amount and refunds nothing twice. Money that arrived after she opened
  it refuses the cancel rather than being kept. Without them, everything held
  is refunded.

  `cancelled_by` (`:customer` or `:shop`) picks who the errors and the email
  speak to.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Expr
  require Logger

  alias Edenflowers.Format
  alias Edenflowers.Payments
  alias Edenflowers.Payments.Changes.CancelOpenPaymentIntent
  alias Edenflowers.Payments.Workers.SendCancelledEmail

  @impl true
  def change(changeset, opts, context) do
    changeset
    |> Ash.Changeset.filter(Ash.Expr.expr(cancellable?))
    |> Ash.Changeset.force_change_attribute(:cancelled_at, DateTime.utc_now())
    |> CancelOpenPaymentIntent.change([], context)
    |> Ash.Changeset.before_transaction(&refund(&1, opts[:cancelled_by]))
    |> Ash.Changeset.after_action(&queue_email(&1, &2, opts[:cancelled_by]))
  end

  defp refund(changeset, cancelled_by) do
    record =
      Ash.load!(changeset.data, [:cancellable?, :amount_held, :paid_through_stripe, :customer_email],
        authorize?: false,
        reuse_values?: false
      )

    held = Decimal.max(record.amount_held, 0)

    with true <- record.cancellable? || {:error, changed_message(cancelled_by)},
         {:ok, kept} <- kept(changeset, held, cancelled_by) do
      to_refund = Decimal.sub(held, kept)
      refunded = Decimal.min(to_refund, Decimal.max(record.paid_through_stripe, 0))

      changeset
      |> Ash.Changeset.force_change_attribute(:kept_amount, kept)
      |> Ash.Changeset.set_context(%{refunded: refunded, to_return: Decimal.sub(to_refund, refunded)})
      |> set_email(record.customer_email)
      |> refund_through_stripe(record, kept, refunded, cancelled_by)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp kept(changeset, held_now, cancelled_by) do
    case {Ash.Changeset.get_argument(changeset, :refund), Ash.Changeset.get_argument(changeset, :held)} do
      {nil, _held} ->
        {:ok, Decimal.new(0)}

      {_refund, nil} ->
        {:error, field: :held, message: "is required with a refund"}

      {refund, held} ->
        cond do
          Decimal.gt?(held_now, held) ->
            {:error, changed_message(cancelled_by)}

          Decimal.negative?(refund) or Decimal.gt?(refund, held) ->
            {:error,
             field: :refund, message: ~t"Enter an amount from €0 to #{amount = Format.currency(held, Format.locale())}."}

          true ->
            {:ok, Decimal.sub(held, refund)}
        end
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
      job = SendCancelledEmail.new_for(record, changeset.context, cancelled_by)

      with {:ok, _job} <- Oban.insert(job) do
        {:ok, record}
      end
    else
      {:ok, record}
    end
  end

  defp changed_message(:customer), do: ~t"This order can no longer be cancelled online. Please contact us."
  defp changed_message(:shop), do: ~t"This changed while you had it open, so it wasn't cancelled."

  defp refused_message(:customer), do: ~t"We couldn't refund your order. Please contact us to cancel it."
  defp refused_message(:shop), do: ~t"Stripe refused the refund, so nothing was cancelled. Check the payment in Stripe."
end
