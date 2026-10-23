defmodule Edenflowers.Orders.Changes.SendReceiptEmail do
  @moduledoc """
  Emails the receipt PDF for an order paid at checkout: with the order
  receipt, or for an Occurrence, Subscription delivery charged. A successful send
  stamps `receipt_emailed_at` and clears `receipt_email_failed_at`. A failed
  send fails the action, so the AshOban trigger retries it and, once attempts
  run out, `record_receipt_email_failure` stamps `receipt_email_failed_at` for
  the admin to see.
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = load_for_send(changeset.data)

      with {:ok, pdf} <- Receipt.generate(order),
           {:ok, _result} <-
             order
             |> email()
             |> Swoosh.Email.attachment(Receipt.attachment(pdf, order.order_reference))
             |> Mailer.deliver() do
        Logger.info("Sent confirmation email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
        |> clear_failure()
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  # An Occurrence's charge is routine; the receipt with thanks is for an order the customer placed.
  defp email(%{origin: :subscription} = order), do: Email.subscription_charged(order)
  defp email(order), do: Email.order_confirmation(order)

  defp load_for_send(order) do
    Ash.load!(
      order,
      [
        :customer_first_name,
        :vat,
        :grand_total,
        :discount,
        :amount_paid,
        :balance,
        :cancellable_by_customer?,
        :cancellable_until,
        line_items: [:subtotal]
      ] ++ Receipt.order_load(),
      authorize?: false
    )
  end

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :receipt_email_failed_at, nil)
end
