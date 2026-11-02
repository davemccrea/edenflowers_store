defmodule Edenflowers.Payments.Changes.SendPaymentReceivedEmail do
  @moduledoc """
  Emails Payment received with the receipt PDF, for the payment of the
  `amount` argument, or else the latest payment. The `email: :receipt`
  option sends a neutral copy of an order's receipt instead of announcing
  a new payment. Fulfillment does not affect either email. A successful send stamps
  `receipt_emailed_at`, and on an order clears `receipt_email_failed_at` and
  logs Jennie's message.
  """
  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Translations

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      record = load_for_send(changeset.data)
      amount = Ash.Changeset.get_argument(changeset, :amount) || latest_payment(record)
      message = Ash.Changeset.get_argument(changeset, :message)

      with {:ok, pdf} <- Receipt.generate(record),
           {:ok, _result} <-
             record
             |> email(amount, message, opts)
             |> Swoosh.Email.attachment(Receipt.attachment(pdf, reference(record)))
             |> Mailer.deliver() do
        Logger.info("Sent payment received email for #{inspect(record.__struct__)} #{record.id}")

        changeset
        |> Ash.Changeset.force_change_attribute(:receipt_emailed_at, DateTime.utc_now())
        |> logged(message)
      else
        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send payment received email: #{inspect(error)}")
      end
    end)
  end

  @doc "The email for `record`'s payment of `amount`, loaded as this change loads it."
  def email(record, amount, message), do: Email.payment_received(record, amount, message)

  defp email(order, _amount, message, email: :receipt), do: Email.purchase_receipt(order, message)
  defp email(record, amount, message, _opts), do: email(record, amount, message)

  defp load_for_send(%Order{} = order) do
    Ash.load!(
      order,
      [:customer_first_name, :vat, :grand_total, :amount_paid, :balance, :payments, line_items: [:subtotal]] ++
        Receipt.order_load(),
      authorize?: false
    )
  end

  # Course names are stored per locale, like the receipt reads them.
  defp load_for_send(%CourseRegistration{} = registration) do
    registration
    |> Ash.load!([:course, :payments, :first_name, :amount_paid, :balance], actor: system_actor())
    |> Translations.in_own_locale()
  end

  @doc "The latest positive payment's amount, or what's been paid when none is loaded."
  def latest_payment(record) do
    record.payments
    |> Enum.filter(&Decimal.positive?(&1.amount))
    |> Enum.max_by(& &1.paid_at, DateTime, fn -> %{amount: record.amount_paid} end)
    |> Map.fetch!(:amount)
  end

  defp reference(%Order{} = order), do: order.order_reference
  defp reference(registration), do: registration.reference

  # Atomic, so a caller holding a copy from before the failure still clears it.
  defp logged(%{resource: Order} = changeset, message) do
    changeset
    |> Ash.Changeset.set_context(%{paper_trail_metadata: %{email_message: message}})
    |> Ash.Changeset.atomic_update(:receipt_email_failed_at, nil)
  end

  defp logged(changeset, _message), do: changeset
end
