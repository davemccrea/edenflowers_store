defmodule Edenflowers.Email.Templates do
  @moduledoc """
  Plain-text email templates compiled at build time. Each entry in `@templates`
  becomes a public render function named after the template, so
  `Edenflowers.Email` can stay focused on building Swoosh envelopes.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "emails"]

  require EEx

  @templates [
    {:order_confirmation, [:assigns]},
    {:payment_received, [:assigns]},
    {:purchase_receipt, [:assigns]},
    {:booking_payment_received, [:assigns]},
    {:payment_reminder, [:assigns]},
    {:booking_payment_reminder, [:assigns]},
    {:invoice, [:assigns]},
    {:credit_note, [:assigns]},
    {:order_details, [:assigns]},
    {:order_updated, [:assigns]},
    {:order_totals, [:assigns]},
    {:order_fulfillment, [:assigns]},
    {:order_payment, [:assigns]},
    {:subscription_payment_failed, [:assigns]},
    {:subscription_set_up, [:assigns]},
    {:subscription_charged, [:assigns]},
    {:subscription_heads_up, [:assigns]},
    {:subscription_cancelled, [:assigns]},
    {:subscription_cancellation_confirmed, [:assigns]},
    {:order_delivered, [:assigns]},
    {:order_left_at_door, [:assigns]},
    {:order_cancelled, [:assigns]},
    {:cancellation_confirmed, [:assigns]},
    {:refund_line, [:assigns]},
    {:cancellation_charge, [:assigns]},
    {:order_refunded, [:assigns]},
    {:course_confirmation, [:assigns]},
    {:course_reminder, [:assigns]},
    {:course_payment, [:assigns]},
    {:booking_cancelled, [:assigns]},
    {:booking_refunded, [:assigns]},
    {:newsletter_welcome, [:assigns]},
    {:already_subscribed, [:assigns]},
    {:otp_sign_in, [:assigns]},
    {:email_change_code, [:assigns]},
    {:wedding_enquiry, [:assigns]},
    {:contact_message, [:assigns]}
  ]

  for {name, args} <- @templates do
    EEx.function_from_file(
      :def,
      name,
      Path.join([__DIR__, "templates", "#{name}.text.eex"]),
      args
    )
  end

  @doc "Jennie's shop, where pickup orders are collected."
  def shop_address, do: "Minimossen, #{~t"Myrvägen 1"}, #{~t"65230 Vasa"}"

  @doc """
  Jennie's own words for this email, as a paragraph after the line saying
  what happened, or nothing.
  """
  def message(nil), do: ""
  def message(""), do: ""
  def message(text), do: String.trim(text) <> "\n\n"

  @doc """
  How a customer pays a cancellation charge still owed: by what the invoices
  they were sent make of it (`Payments.Changes.Cancel.money/2`), else by a
  new invoice on invoice terms.
  """
  def collect_line(%{earlier_invoices: :replace, earlier_invoice_count: count}) do
    gettext_comment("After the cancellation charge: \"it\" is the charge, or the part of it still to pay.")

    dngettext(
      "emails",
      "I'll cancel my earlier invoice and send you a new one for it.",
      "I'll cancel my earlier invoices and send you a new one for it.",
      count
    )
  end

  def collect_line(%{earlier_invoices: :stand, earlier_invoice_count: count}) do
    gettext_comment(
      "After the cancellation charge: the invoices sent before cancelling ask for just what is left of it."
    )

    dngettext(
      "emails",
      "My earlier invoice already asks for it, so please pay that one.",
      "My earlier invoices already ask for it, so please pay those.",
      count
    )
  end

  def collect_line(%{earlier_invoices: :top_up, earlier_invoice_count: count} = assigns) do
    gettext_comment("After the cancellation charge: %{amount} of it is already on the invoices sent before cancelling.")

    dngettext(
      "emails",
      "My earlier invoice asks for %{amount} of it, and I'll send you an invoice for the rest.",
      "My earlier invoices ask for %{amount} of it, and I'll send you an invoice for the rest.",
      count,
      amount: assigns.format_currency.(assigns.invoiced)
    )
  end

  def collect_line(%{invoice?: true}), do: ~t"I'll send you an invoice for it."
  def collect_line(_assigns), do: ~t"I'll be in touch about how to pay it."

  @doc "When each invoice the customer was sent is due, or was, if it is overdue, as one line."
  def invoices_due_line(invoices, format_date) do
    Enum.map_join(invoices, " ", fn invoice ->
      date = format_date.(invoice.due_date)

      if invoice.overdue?, do: overdue_line(invoice.number, date), else: due_line(invoice.number, date)
    end)
  end

  # gettext_comment/1 attaches to the next message extracted, so each line has a function of its own.

  defp due_line(number, date) do
    gettext_comment("%{date} is a weekday and date, as \"Monday 30.11.2026\".")
    dgettext("emails", "My invoice %{number} is due on %{date}.", number: number, date: date)
  end

  defp overdue_line(number, date) do
    gettext_comment("%{date} is a weekday and date, as \"Monday 30.11.2026\", now past.")
    dgettext("emails", "My invoice %{number} was due on %{date}.", number: number, date: date)
  end

  @doc "How the emails Jennie sends are signed."
  def signature do
    """
    Jennie
    Eden Flowers
    #{shop_address()}
    040 220 9494 · edenflowers.fi\
    """
  end
end
