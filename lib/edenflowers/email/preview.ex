defmodule Edenflowers.Email.Preview do
  @moduledoc """
  What one of Jennie's actions would email the customer, built by the real
  builder in `Edenflowers.Email` from the real order or booking, so she can
  read it before it goes. Building never sends or queues anything.

  Attachments are named, not made: the receipt PDF and the doorstep photo
  are empty stand-ins.
  """

  import Edenflowers.Actors

  alias Edenflowers.Accounts.Calculations.NamePart
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.CourseRegistration.Changes.PriceBooking
  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Order.Changes.SendReceiptEmail
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Orders.Subscription.Changes.SendSubscriptionCancelledEmail
  alias Edenflowers.Payments.Changes.Cancel
  alias Edenflowers.Payments.Changes.SendInvoice
  alias Edenflowers.Payments.Changes.SendPaymentReceivedEmail
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.GiftVoucherPdf
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Translations

  @doc """
  The email `kind` would send for `record`, in the customer's language.
  `inputs` holds what Jennie has entered so far, for some
  kinds: the `refund` amount, the cancellation `charge`, the
  `payment_method` or whether the `photo?` goes with it (else what
  `:mark_fulfilled` stored). A payment link that sending opens shows
  `Edits.placeholder_token/0` as its token.
  """
  def build(:invoice, %Invoice{} = invoice, _inputs), do: build_invoice(invoice)

  def build(:credit_note, %CreditNote{} = credit_note, _inputs),
    do: credit_note |> Ash.load!(:invoice, authorize?: false) |> build_credit_note()

  def build(kind, %Order{} = order, inputs) do
    order = Ash.load!(order, order_load(kind), authorize?: false, reuse_values?: false)
    order_email(kind, order, inputs)
  end

  def build(:subscription_cancelled, %Subscription{} = subscription, _inputs) do
    subscription = SendSubscriptionCancelledEmail.load_for_send(subscription)
    Email.subscription_cancelled(subscription, SendSubscriptionCancelledEmail.charged_on(subscription))
  end

  def build(kind, %CourseRegistration{} = registration, inputs) do
    registration
    |> Ash.load!(booking_load(kind), actor: system_actor(), reuse_values?: false)
    |> translated()
    |> then(&booking_email(kind, &1, inputs))
  end

  @doc """
  The Order details or Order updated email for an order Jennie is entering
  or editing, from the form's `changeset` and its `price` from
  `Edenflowers.Orders.quote_entered_order/3`, before anything is saved. `order` is the
  order being edited, or nil.
  """
  def build_entered(kind, changeset, price, order) do
    {:ok, entered} = Ash.Changeset.apply_attributes(changeset, force?: true)

    entered = %{
      entered
      | customer_first_name: NamePart.first(entered.customer_name),
        line_items: Enum.map(price.lines, &%{quantity: &1.quantity, product_name: &1.name, subtotal: &1.total}),
        fulfillment_fee: price.fulfillment_fee,
        grand_total: price.total,
        amount_paid: price.paid,
        balance: price.balance
    }

    url = if entered_link?(entered, order), do: link_url(entered)

    case kind do
      :order_details -> Email.order_details(entered, url)
      :order_updated -> Email.order_updated(entered, url)
    end
  end

  @doc """
   The confirmation email for a booking Jennie is entering for `course`, from
  the form's `changeset`, before anything is saved.
  """
  def build_entered_booking(changeset, course) do
    {:ok, entered} = Ash.Changeset.apply_attributes(changeset, force?: true)
    seats = entered.seats || 1
    amount_paid = Ash.Changeset.get_argument(changeset, :amount) || Decimal.new(0)

    entered =
      %{
        entered
        | course: course,
          first_name: NamePart.first(entered.name),
          seats: seats,
          amount_paid: amount_paid,
          balance: Decimal.sub(PriceBooking.amount(course, seats), amount_paid),
          payment_link_token: if(entered.payment_terms == :payment_link, do: Edits.placeholder_token())
      }
      |> translated()

    booking_email(:confirmation, entered, %{})
  end

  @doc "The Credit note email for `credit_note` (with its `invoice` loaded)."
  def build_credit_note(%CreditNote{} = credit_note) do
    credit_note
    |> Email.credit_note()
    |> Swoosh.Email.attachment(InvoicePdf.attachment("", credit_note))
  end

  @doc "The Invoice email `:send` would send for `invoice` now."
  def build_invoice(%Invoice{} = invoice) do
    invoice
    |> SendInvoice.load_for_email()
    |> Email.invoice()
    |> Swoosh.Email.attachment(InvoicePdf.attachment("", invoice))
  end

  # Placing opens a link for payment-link terms; an edited order keeps the one it has.
  defp entered_link?(entered, nil), do: entered.payment_terms == :payment_link
  defp entered_link?(_entered, order), do: order.payment_link_open?

  defp order_load(:fulfillment), do: [:customer_first_name, :recipient_first_name]

  defp order_load(:gift_voucher),
    do: [:customer_first_name, :voucher_card_ready_on, :voucher_card_to_hand_over?, gift_voucher_line: [:gift_voucher]]

  defp order_load(:cancelled), do: [:customer_first_name, :payments | Cancel.load()]
  defp order_load(:refunded), do: [:customer_first_name, :payments, :paid_through_stripe]
  defp order_load(:receipt), do: [:gift_voucher_sale? | order_load(:gift_voucher)] ++ totals_load()
  defp order_load(_kind), do: totals_load()

  defp totals_load,
    do: [
      :customer_first_name,
      :grand_total,
      :amount_paid,
      :balance,
      :payment_link_open?,
      :payments,
      line_items: [:subtotal]
    ]

  defp order_email(:order_details, order, _inputs),
    do: Email.order_details(order, EdenflowersWeb.PaymentLink.url_if_open(order))

  # Sending it opens the link, so it reads as it will once open.
  defp order_email(:payment_link, order, _inputs),
    do: Email.order_details(order, link_url(order))

  defp order_email(:payment_reminder, order, _inputs),
    do: Email.payment_reminder(order, link_url(order))

  # A Gift voucher sale's payment is answered with the voucher itself.
  defp order_email(:receipt, %{gift_voucher_sale?: true} = order, inputs), do: order_email(:gift_voucher, order, inputs)

  defp order_email(:receipt, order, inputs), do: payment_receipt(order, inputs, order.order_reference)

  defp order_email(:gift_voucher, order, _inputs) do
    order
    |> SendReceiptEmail.gift_voucher_email()
    |> Swoosh.Email.attachment(GiftVoucherPdf.attachment("", order.order_reference))
    |> Swoosh.Email.attachment(Receipt.attachment("", order.order_reference))
  end

  defp order_email(:fulfillment, order, inputs) do
    if Map.get(inputs, :photo?, order.email_delivery_photo),
      do: Email.order_left_at_door(order, ""),
      else: Email.order_delivered(order)
  end

  defp order_email(:cancelled, order, inputs) do
    Email.cancelled(order, Cancel.money(order, charge(order, inputs)))
  end

  defp order_email(:refunded, order, inputs), do: Email.refunded(order, refund_details(inputs))

  defp booking_load(:cancelled), do: [:course, :first_name, :payments | Cancel.load()]
  defp booking_load(:refunded), do: [:course, :first_name, :payments, :paid_through_stripe]

  defp booking_load(_kind),
    do: [
      :course,
      :first_name,
      :amount_paid,
      :balance,
      :payments,
      :payment_link_open?
    ]

  defp booking_email(:confirmation, registration, _inputs) do
    email = Email.course_confirmation(registration)

    if Decimal.positive?(registration.amount_paid),
      do: Swoosh.Email.attachment(email, Receipt.attachment("", registration.reference)),
      else: email
  end

  defp booking_email(:course_reminder, registration, _inputs),
    do: Email.course_reminder(registration)

  defp booking_email(:payment_link, registration, _inputs) do
    Email.payment_reminder(registration, link_url(registration))
  end

  defp booking_email(:payment_reminder, registration, _inputs),
    do: Email.payment_reminder(registration, link_url(registration))

  defp booking_email(:receipt, registration, inputs), do: payment_receipt(registration, inputs, registration.reference)

  defp booking_email(:cancelled, registration, inputs) do
    money = Cancel.money(registration, charge(registration, inputs))
    Email.cancelled(registration, money)
  end

  defp booking_email(:refunded, registration, inputs), do: Email.refunded(registration, refund_details(inputs))

  defp payment_receipt(record, inputs, reference) do
    amount = decimal(inputs[:amount]) || SendPaymentReceivedEmail.latest_payment(record)

    email =
      if match?(%Order{}, record) and is_nil(inputs[:amount]),
        do: Email.purchase_receipt(record),
        else: SendPaymentReceivedEmail.email(record, amount)

    Swoosh.Email.attachment(email, Receipt.attachment("", reference))
  end

  # A link not yet opened has no token until sending opens it.
  defp link_url(%{payment_link_token: nil} = payable),
    do: EdenflowersWeb.PaymentLink.url_for(%{payable | payment_link_token: Edits.placeholder_token()})

  defp link_url(payable), do: EdenflowersWeb.PaymentLink.url_for(payable)

  defp refund_details(inputs),
    do: %{amount: refund(inputs), payment_method: inputs[:payment_method] || :stripe}

  # An empty charge cancels with the default, so it reads as that.
  defp charge(record, inputs), do: decimal(inputs[:charge]) || record.default_cancellation_charge

  defp refund(inputs), do: decimal(inputs[:refund]) || Decimal.new(0)

  # What Jennie has typed so far, which may not be a number yet.
  defp decimal(text) do
    case Ash.Type.cast_input(Edenflowers.Types.Price, text) do
      {:ok, %Decimal{} = amount} -> Decimal.max(amount, 0)
      _ -> nil
    end
  end

  defp translated(%CourseRegistration{} = registration), do: Translations.in_own_locale(registration)

  defp translated(order), do: order
end
