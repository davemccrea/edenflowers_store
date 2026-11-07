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
      order = load_for_send(changeset.data)

      # A queued confirmation must not promise flowers or a usable voucher after cancellation.
      if order.fulfillment_status == :cancelled,
        do: changeset,
        else: deliver(changeset, order)
    end)
  end

  defp deliver(changeset, order) do
    edits = Edits.from_changeset(changeset)

    with {:ok, pdf} <- Receipt.generate(order),
         {:ok, email} <- with_voucher(email(order), order),
         {:ok, _result} <-
           email
           |> Edits.apply_to(edits)
           |> Swoosh.Email.attachment(Receipt.attachment(pdf, order.order_reference))
           |> Mailer.deliver() do
      Logger.info("Sent confirmation email for order #{order.id}")

      changeset
      |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
      |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(edits)})
      |> clear_failure()
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
    end
  end

  # An Occurrence's charge is routine; the receipt with thanks is for an order the customer placed.
  defp email(%{origin: :subscription} = order), do: Email.subscription_charged(order)
  defp email(%{gift_voucher_sale?: true} = order), do: gift_voucher_email(order)
  defp email(order), do: Email.order_confirmation(order)

  @doc """
  A Gift voucher sale's email, without its attachments. It names the day the
  gift card is ready only while the card is still to collect, so a resend
  after the buyer collected it doesn't promise it again.
  """
  def gift_voucher_email(order) do
    Email.gift_voucher_sold(order, if(order.voucher_card_to_hand_over?, do: order.voucher_card_ready_on))
  end

  @doc "Attaches a Gift voucher sale's one voucher as a PDF, beside the receipt when there is one."
  def with_voucher(email, order) do
    case order.gift_voucher_line do
      nil ->
        {:ok, email}

      %{gift_voucher: voucher} ->
        with {:ok, pdf} <- GiftVoucherPdf.generate(%{voucher | line_item: %{order: order}}) do
          {:ok, Swoosh.Email.attachment(email, GiftVoucherPdf.attachment(pdf, order.order_reference))}
        end
    end
  end

  @doc "The order with what its emails and their attachments need."
  def load_for_send(order) do
    Ash.load!(
      order,
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
      ] ++ Receipt.order_load(),
      authorize?: false
    )
  end

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :receipt_email_failed_at, nil)
end
