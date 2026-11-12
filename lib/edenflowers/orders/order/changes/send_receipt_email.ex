defmodule Edenflowers.Orders.Order.Changes.SendReceiptEmail do
  @moduledoc """
  Emails the receipt PDF for an order paid at checkout: with the order
  receipt, or for an Occurrence, Subscription delivery charged. A successful send
  stamps `receipt_emailed_at` and clears `receipt_email_failed_at`. A failed
  send fails the action, so the AshOban trigger retries it and, once attempts
  run out, `record_receipt_email_failure` stamps `receipt_email_failed_at` for
  the admin to see.

  Jennie's `email_gift_voucher` resends a Gift voucher sale's email to the
  buyer the same way, with her rewrite if she made one; the log records it.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Payments.GiftVoucherPdf

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = Ash.load!(changeset.data, load(), authorize?: false)

      # A queued confirmation must not promise flowers or a usable voucher after cancellation.
      if order.fulfillment_status == :cancelled do
        Logger.info("Skipped confirmation email for cancelled order #{order.id}")
        changeset
      else
        deliver(changeset, order)
      end
    end)
  end

  defp deliver(changeset, order) do
    edits = Edits.from_changeset(changeset)

    with {:ok, receipt_pdf} <- Receipt.generate(order),
         {:ok, voucher_pdf} <- voucher_pdf(order),
         {:ok, _result} <- order |> email(receipt_pdf, voucher_pdf) |> Edits.apply_to(edits) |> Mailer.deliver() do
      Logger.info("Sent confirmation email for order #{order.id}")

      changeset
      |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
      |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(edits)})
      |> clear_failure()
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
    end
  end

  @doc """
  The email for an order loaded with `load/0`, with `receipt_pdf` attached
  and, for a Gift voucher sale, `voucher_pdf` before it.
  """
  def email(order, receipt_pdf, voucher_pdf) do
    order
    |> email()
    |> with_voucher(order, voucher_pdf)
    |> Swoosh.Email.attachment(Receipt.attachment(receipt_pdf, order.order_reference))
  end

  # An Occurrence's charge is routine; the receipt with thanks is for an order the customer placed.
  defp email(%{origin: :subscription} = order), do: Email.subscription_charged(order)
  defp email(%{gift_voucher_sale?: true} = order), do: gift_voucher_email(order)
  defp email(order), do: Email.order_confirmation(order)

  # It names the day the gift card is ready only while the card is still to
  # collect, so a resend after the buyer collected it doesn't promise it again.
  defp gift_voucher_email(order) do
    Email.gift_voucher_sold(order, if(order.voucher_card_to_hand_over?, do: order.voucher_card_ready_on))
  end

  defp with_voucher(email, %{gift_voucher_line: nil}, _voucher_pdf), do: email

  defp with_voucher(email, order, voucher_pdf),
    do: Swoosh.Email.attachment(email, GiftVoucherPdf.attachment(voucher_pdf, order.order_reference))

  defp voucher_pdf(%{gift_voucher_line: nil}), do: {:ok, nil}

  defp voucher_pdf(%{gift_voucher_line: %{gift_voucher: voucher}} = order),
    do: GiftVoucherPdf.generate(%{voucher | line_item: %{order: order}})

  @doc "What the order is loaded with to build its email and PDF attachments."
  def load do
    [
      :customer_first_name,
      :recipient_first_name,
      :vat,
      :grand_total,
      :discount,
      :amount_paid,
      :balance,
      :cancellable_by_customer?,
      :cancellable_until,
      :voucher_card_ready_on,
      :voucher_card_to_hand_over?,
      line_items: [:subtotal]
    ] ++ Receipt.order_load()
  end

  # Clear the failure in the database even if the caller's stale record already has a nil timestamp.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :receipt_email_failed_at, nil)
end
