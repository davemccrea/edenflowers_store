defmodule Edenflowers.Email.Preview do
  @moduledoc """
  What one of Jennie's actions would email the customer, built by the real
  builder in `Edenflowers.Email` from the real order or booking, so she can
  read it before it goes. Building never sends or queues anything.

  Attachments are named, not made: the receipt PDF and the doorstep photo
  are empty stand-ins.
  """

  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Payments.Changes.Cancel
  alias Edenflowers.Translations

  @doc """
  The email `kind` would send for `record`, in `locale` or else the
  customer's own. `inputs` holds what Jennie has entered so far: her
  `message`, and for some kinds the `refund` amount, the `payment_method`
  or whether the `photo?` goes with it (else what `:mark_fulfilled` stored).
  """
  def build(kind, record, inputs, locale \\ nil)

  def build(kind, %Order{} = order, inputs, locale) do
    order = order |> Ash.load!(order_load(kind), authorize?: false, reuse_values?: false) |> in_locale(locale)
    order_email(kind, order, inputs)
  end

  def build(kind, %CourseRegistration{} = registration, inputs, locale) do
    registration
    |> Ash.load!(booking_load(kind), actor: system_actor(), reuse_values?: false)
    |> in_locale(locale)
    |> then(&booking_email(kind, &1, inputs))
  end

  defp order_load(:receipt), do: [:customer_first_name, :vat, :cancellable_by_customer?, :cancellable_until]
  defp order_load(:fulfillment), do: [:customer_first_name, :recipient_first_name]

  defp order_load(kind) when kind in [:cancelled, :refunded],
    do: [:customer_first_name, :payments, :paid_through_stripe]

  defp order_load(_details),
    do: [:customer_first_name, :grand_total, :amount_paid, :balance, :payment_link_open?, line_items: [:subtotal]]

  defp order_email(:order_details, order, inputs),
    do: Email.order_details(order, payment_link_url(order), inputs[:message])

  # Sending it opens the link, so it reads as it will once open.
  defp order_email(:payment_link, order, inputs),
    do: Email.order_details(order, link_url(order), inputs[:message])

  defp order_email(:receipt, order, inputs) do
    order
    |> Email.order_confirmation(inputs[:message])
    |> Swoosh.Email.attachment(Receipt.attachment("", order.order_reference))
  end

  defp order_email(:fulfillment, order, inputs),
    do: Email.order_delivered(order, if(Map.get(inputs, :photo?, order.email_delivery_photo), do: ""), inputs[:message])

  defp order_email(:cancelled, order, inputs) do
    Email.cancelled(%{order | cancellation_reason: inputs[:message]}, Cancel.money(order, refund(inputs)), :shop)
  end

  defp order_email(:refunded, order, inputs), do: Email.refunded(order, refund_details(inputs))

  defp booking_load(kind) when kind in [:cancelled, :refunded],
    do: [:course, :first_name, :payments, :paid_through_stripe]

  defp booking_load(_kind), do: [:course, :first_name, :amount_paid, :balance, :payment_link_open?]

  defp booking_email(:confirmation, %{balance: balance} = registration, inputs) do
    if Decimal.positive?(balance),
      do: booking_email(:payment_link, registration, inputs),
      else:
        registration
        |> Email.course_confirmation(inputs[:message])
        |> Swoosh.Email.attachment(Receipt.attachment("", registration.reference))
  end

  defp booking_email(:payment_link, registration, inputs),
    do: Email.course_payment_link(registration, link_url(registration), inputs[:message])

  defp booking_email(:cancelled, registration, inputs) do
    money = Cancel.money(registration, refund(inputs))
    Email.cancelled(%{registration | cancellation_reason: inputs[:message]}, money, :shop)
  end

  defp booking_email(:refunded, registration, inputs), do: Email.refunded(registration, refund_details(inputs))

  # A link not yet opened has no token until sending opens it.
  defp link_url(%{payment_link_token: nil}), do: EdenflowersWeb.Endpoint.url() <> "/pay/…"
  defp link_url(payable), do: EdenflowersWeb.PaymentLink.url_for(payable)

  defp payment_link_url(%{payment_link_open?: true} = order), do: EdenflowersWeb.PaymentLink.url_for(order)
  defp payment_link_url(_order), do: nil

  defp refund_details(inputs),
    do: %{amount: refund(inputs), payment_method: inputs[:payment_method] || :stripe, note: inputs[:message]}

  # What Jennie has typed so far, which may not be a number yet.
  defp refund(inputs) do
    case Decimal.parse(String.replace(inputs[:refund] || "", ",", ".")) do
      {amount, ""} -> Decimal.max(amount, 0)
      _ -> Decimal.new(0)
    end
  end

  defp in_locale(record, nil), do: translated(record)
  defp in_locale(record, locale), do: translated(%{record | locale: locale})

  # Course names are stored per locale, like the senders read them.
  defp translated(%CourseRegistration{} = registration),
    do: Map.update!(registration, :course, &Translations.translate(&1, String.to_existing_atom(registration.locale)))

  defp translated(order), do: order
end
