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
  alias Edenflowers.Orders.Changes.SendSubscriptionCancelledEmail
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments.Changes.Cancel
  alias Edenflowers.Payments.Changes.SendPaymentReceivedEmail
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

  def build(:subscription_cancelled, %Subscription{} = subscription, inputs, locale) do
    subscription = SendSubscriptionCancelledEmail.load_for_send(%{subscription | locale: locale || subscription.locale})

    Email.subscription_cancelled(
      subscription,
      SendSubscriptionCancelledEmail.charged_on(subscription),
      inputs[:message]
    )
  end

  def build(kind, %CourseRegistration{} = registration, inputs, locale) do
    registration
    |> Ash.load!(booking_load(kind), actor: system_actor(), reuse_values?: false)
    |> in_locale(locale)
    |> then(&booking_email(kind, &1, inputs))
  end

  @doc """
  The Order details or Order updated email for an order Jennie is entering
  or editing, from the form's `changeset` and its `price` from
  `Edenflowers.Orders.EnteredPrice`, before anything is saved. `order` is the
  order being edited, or nil.
  """
  def build_entered(kind, changeset, price, order, inputs, locale \\ nil) do
    {:ok, entered} = Ash.Changeset.apply_attributes(changeset, force?: true)
    paid = if order, do: order.amount_paid, else: Decimal.new(0)
    balance = Decimal.sub(price.total, paid)

    entered = %{
      entered
      | locale: locale || entered.locale,
        customer_first_name: Edenflowers.Accounts.Calculations.FirstName.extract(entered.customer_name),
        line_items: Enum.map(price.lines, &%{quantity: &1.quantity, product_name: &1.name, subtotal: &1.total}),
        fulfillment_fee: price.fulfillment_fee,
        grand_total: price.total,
        amount_paid: paid,
        balance: balance
    }

    url = if entered_link?(entered, order), do: link_url(entered)

    case kind do
      :order_details -> Email.order_details(entered, url, inputs[:message])
      :order_updated -> Email.order_updated(entered, url, inputs[:message])
    end
  end

  @doc """
  The payment link email for a booking Jennie is adding on `course`, from
  the form's `changeset`, before anything is saved.
  """
  def build_entered_booking(changeset, course, inputs, locale \\ nil) do
    {:ok, entered} = Ash.Changeset.apply_attributes(changeset, force?: true)
    seats = entered.seats || 1

    entered =
      %{
        entered
        | locale: locale || entered.locale,
          course: course,
          first_name: Edenflowers.Accounts.Calculations.FirstName.extract(entered.name),
          seats: seats,
          balance: Decimal.mult(course.price, seats),
          # Saving opens the link with a token of its own.
          payment_link_token: nil
      }
      |> translated()

    booking_email(:payment_link, entered, inputs)
  end

  # Placing opens a link for payment-link terms; an edited order keeps the one it has.
  defp entered_link?(entered, nil), do: entered.payment_terms == :payment_link
  defp entered_link?(_entered, order), do: order.payment_link_open?

  defp order_load(:fulfillment), do: [:customer_first_name, :recipient_first_name]

  defp order_load(kind) when kind in [:cancelled, :refunded],
    do: [:customer_first_name, :payments, :paid_through_stripe]

  defp order_load(_kind),
    do: [
      :customer_first_name,
      :grand_total,
      :amount_paid,
      :balance,
      :payment_link_open?,
      :payments,
      line_items: [:subtotal]
    ]

  defp order_email(:order_details, order, inputs),
    do: Email.order_details(order, payment_link_url(order), inputs[:message])

  # Sending it opens the link, so it reads as it will once open.
  defp order_email(:payment_link, order, inputs),
    do: Email.order_details(order, link_url(order), inputs[:message])

  # A payment being recorded reads as it will once it's in; from the menu,
  # it's the latest payment again.
  defp order_email(:payment_reminder, order, inputs),
    do: Email.payment_reminder(order, link_url(order), inputs[:message])

  defp order_email(:receipt, order, inputs) do
    {order, amount} =
      case decimal(inputs[:amount]) do
        nil ->
          {order, latest_payment(order)}

        amount ->
          {%{order | amount_paid: Decimal.add(order.amount_paid, amount), balance: Decimal.sub(order.balance, amount)},
           amount}
      end

    order
    |> SendPaymentReceivedEmail.email(amount, inputs[:message])
    |> Swoosh.Email.attachment(Receipt.attachment("", order.order_reference))
  end

  defp order_email(:fulfillment, order, inputs) do
    if Map.get(inputs, :photo?, order.email_delivery_photo),
      do: Email.order_left_at_door(order, "", inputs[:message]),
      else: Email.order_delivered(order, inputs[:message])
  end

  defp order_email(:cancelled, order, inputs) do
    Email.cancelled(%{order | cancellation_reason: inputs[:message]}, Cancel.money(order, refund(inputs)))
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

  # After the course, the link goes in a Payment reminder, as the senders send it.
  defp booking_email(:payment_link, registration, inputs) do
    if Date.before?(registration.course.date, Edenflowers.ShopTime.today()),
      do: Email.payment_reminder(registration, link_url(registration), inputs[:message]),
      else: Email.course_payment_link(registration, link_url(registration), inputs[:message])
  end

  defp booking_email(:payment_reminder, registration, inputs),
    do: Email.payment_reminder(registration, link_url(registration), inputs[:message])

  defp booking_email(:cancelled, registration, inputs) do
    money = Cancel.money(registration, refund(inputs))
    Email.cancelled(%{registration | cancellation_reason: inputs[:message]}, money)
  end

  defp booking_email(:refunded, registration, inputs), do: Email.refunded(registration, refund_details(inputs))

  # A link not yet opened has no token until sending opens it.
  defp link_url(%{payment_link_token: nil}), do: EdenflowersWeb.Endpoint.url() <> "/pay/…"
  defp link_url(payable), do: EdenflowersWeb.PaymentLink.url_for(payable)

  defp payment_link_url(%{payment_link_open?: true} = order), do: EdenflowersWeb.PaymentLink.url_for(order)
  defp payment_link_url(_order), do: nil

  defp refund_details(inputs),
    do: %{amount: refund(inputs), payment_method: inputs[:payment_method] || :stripe, note: inputs[:message]}

  defp refund(inputs), do: decimal(inputs[:refund]) || Decimal.new(0)

  # What Jennie has typed so far, which may not be a number yet.
  defp decimal(nil), do: nil

  defp decimal(text) do
    case Decimal.parse(String.replace(text, ",", ".")) do
      {amount, ""} -> Decimal.max(amount, 0)
      _ -> nil
    end
  end

  defp latest_payment(order) do
    order.payments
    |> Enum.filter(&Decimal.positive?(&1.amount))
    |> Enum.max_by(& &1.paid_at, DateTime, fn -> %{amount: order.amount_paid} end)
    |> Map.fetch!(:amount)
  end

  defp in_locale(record, nil), do: translated(record)
  defp in_locale(record, locale), do: translated(%{record | locale: locale})

  # Course names are stored per locale, like the senders read them.
  defp translated(%CourseRegistration{} = registration),
    do: Map.update!(registration, :course, &Translations.translate(&1, String.to_existing_atom(registration.locale)))

  defp translated(order), do: order
end
