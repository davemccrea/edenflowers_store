defmodule Edenflowers.Email do
  @moduledoc """
  Builds the app's Swoosh email envelopes. Bodies are rendered by
  `Edenflowers.Email.Templates`; subjects are localised per the order's locale.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  import Swoosh.Email

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email.Templates
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.ShopNotice

  @doc """
  The receipt for an Online Order paid at checkout: when and where, what was
  bought, and until when the customer can cancel it themselves. Expects
  `:customer_first_name`, `:grand_total`, `:discount`, `:amount_paid`,
  `:balance`, `:cancellable_by_customer?`, `:cancellable_until` and
  `line_items: [:subtotal]` loaded.
  """
  def order_confirmation(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers order for #{date = short_date(order)}")
      |> text_body(
        Templates.order_confirmation(%{
          order: order,
          format_date: &Format.weekday_date(&1, order.locale),
          format_currency: &Format.currency(&1, order.locale),
          fulfillment_on: fulfillment_on(order),
          account_url: account_url()
        })
      )
    end)
  end

  @doc """
  Tells the customer their payment of `amount` arrived outside checkout,
  through a payment link or recorded by Jennie, with the receipt the
  sender attaches. Never asks for more, even if some is still owed. For an
  order, expects `:customer_first_name`, `:grand_total`, `:amount_paid`,
  `:balance` and `line_items: [:subtotal]` loaded; for a booking,
  `:course` (translated), `:first_name`, `:amount_paid` and `:balance`.
  """
  def payment_received(record, amount, message \\ nil)

  def payment_received(%Order{} = order, amount, message) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Payment received for your order for #{date = short_date(order)}")
      |> text_body(
        Templates.payment_received(%{
          order: order,
          amount: amount,
          message: message,
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  def payment_received(%CourseRegistration{} = registration, amount, message) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(
        ~t"Payment received for #{course = registration.course.name}, #{date = Format.day_month(registration.course.date, registration.locale)}"
      )
      |> text_body(
        Templates.booking_payment_received(%{
          registration: registration,
          amount: amount,
          message: message,
          format_date: &Format.weekday_date(&1, registration.locale),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

  @doc """
  The receipt for an order handed over and paid in full, as a sale is in
  the shop, with the PDF the sender attaches. Says nothing about where it
  was paid, which may be any time. Loads as `payment_received/3`.
  """
  def purchase_receipt(%Order{} = order, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your receipt from Eden Flowers")
      |> text_body(
        Templates.purchase_receipt(%{
          order: order,
          message: message,
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  Jennie's reminder of what is still owed on an order or booking, with the
  payment link to pay it. Only ever sent by hand. Loads as
  `payment_received/3`.
  """
  def payment_reminder(record, payment_link_url, message \\ nil)

  def payment_reminder(%Order{} = order, payment_link_url, message) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"A reminder about your order for #{date = short_date(order)}")
      |> text_body(
        Templates.payment_reminder(%{
          order: order,
          date: Format.weekday_date(order.fulfillment_date, order.locale),
          message: message,
          payment_link_url: payment_link_url,
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  def payment_reminder(%CourseRegistration{} = registration, payment_link_url, message) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"A reminder about your booking on #{course = registration.course.name}")
      |> text_body(
        Templates.booking_payment_reminder(%{
          registration: registration,
          message: message,
          payment_link_url: payment_link_url,
          format_date: &Format.weekday_date(&1, registration.locale),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

  @doc """
  What Jennie and the customer agreed for a custom order she placed, and how
  to pay. Once the order is handed over it leaves out the delivery or pickup
  line. Expects `:customer_first_name`, `:grand_total`, `:amount_paid`,
  `:balance` and `line_items: [:subtotal]` loaded.
  """
  def order_details(order, payment_link_url, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers order for #{date = short_date(order)}")
      |> text_body(Templates.order_details(order_assigns(order, payment_link_url, message)))
    end)
  end

  @doc """
  The whole order as it now stands after Jennie edited it, since the
  customer pays against the whole. How to pay only while something is owed.
  Loads as `order_details/3`.
  """
  def order_updated(order, payment_link_url, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your updated Eden Flowers order for #{date = short_date(order)}")
      |> text_body(Templates.order_updated(order_assigns(order, payment_link_url, message)))
    end)
  end

  defp order_assigns(order, payment_link_url, message) do
    %{
      order: order,
      message: message,
      payment_link_url: payment_link_url,
      fulfillment_on: fulfillment_on(order),
      format_currency: &Format.currency(&1, order.locale)
    }
  end

  @doc """
  A matter-of-fact note that a subscription's saved card was charged for
  its next delivery or pickup, with the receipt the sender attaches. Expects
  `:amount_paid` and `:line_items` loaded.
  """
  def subscription_charged(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(automated_from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your flowers for #{date = short_date(order)}")
      |> text_body(
        Templates.subscription_charged(%{
          order: order,
          product: hd(order.line_items).product_name,
          date: Format.weekday_date(order.fulfillment_date, order.locale),
          account_url: account_url(),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  An Occurrence whose saved card was refused: the flowers still come, and
  the payment link pays for them. Expects `:customer_first_name`, `:balance`
  and `:line_items` loaded.
  """
  def subscription_payment_failed(order, payment_link_url) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Payment needed for your flowers on #{date = short_date(order)}")
      |> text_body(
        Templates.subscription_payment_failed(%{
          order: order,
          product: hd(order.line_items).product_name,
          date: Format.weekday_date(order.fulfillment_date, order.locale),
          payment_link_url: payment_link_url,
          account_url: account_url(),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  # Subjects name the day, "Saturday 14.11.", so the customer can tell orders apart.
  defp short_date(order), do: Format.weekday_day_month(order.fulfillment_date, order.locale)

  # A window reads as the course emails write theirs: "Saturday 14.11.2026, 12:00–16:00".
  defp fulfillment_on(order) do
    date = Format.weekday_date(order.fulfillment_date, order.locale)

    case order do
      %{fulfillment_time_start: nil} ->
        date

      %{fulfillment_time_end: nil} ->
        "#{date} #{Format.fulfillment_time(order, order.locale)}"

      %{fulfillment_time_start: start, fulfillment_time_end: finish} ->
        "#{date}, #{Format.time(start, order.locale)}–#{Format.time(finish, order.locale)}"
    end
  end

  @doc """
  What a customer is sent once their Subscription is started: what comes and
  how often, what each costs, the first two dates, and where to change it.
  The first order's receipt goes separately. Expects `product_variant: :product`
  (translated into the subscription's locale),
  `:fulfillment_option`, `:first_delivery_date`, `:first_order_fulfillment_fee`
  and `user: [:first_name]` loaded.
  """
  def subscription_set_up(subscription) do
    EdenflowersWeb.Gettext.with_app_locale(subscription.locale, fn ->
      new()
      |> from(from_address())
      |> to(to_string(subscription.user.email))
      |> bcc(record_copy_address())
      |> subject(~t"Your #{product = subscription.product_variant.product.name} subscription is set up")
      |> text_body(
        Templates.subscription_set_up(%{
          subscription: subscription,
          pickup?: subscription.fulfillment_option.fulfillment_method == :pickup,
          size: EdenflowersWeb.Admin.Components.variant_size_label(subscription.product_variant.size),
          interval: EdenflowersWeb.Checkout.Fields.interval_label(subscription.interval_weeks),
          price: Format.currency(subscription_price(subscription), subscription.locale),
          charge_days: Edenflowers.Orders.Subscription.lead_days(),
          change_days: Edenflowers.Orders.Subscription.cutoff_days() + 1,
          account_url: account_url(),
          format_date: &Format.weekday_date(&1, subscription.locale)
        })
      )
    end)
  end

  @doc """
  Tells the customer Jennie cancelled their subscription, with her message,
  and `charged_on`, the day of a delivery already charged that still comes,
  if there is one. Loads as `Changes.SendSubscriptionCancelledEmail` loads it.
  """
  def subscription_cancelled(subscription, charged_on, message \\ nil) do
    product = subscription.product_variant.product.name

    EdenflowersWeb.Gettext.with_app_locale(subscription.locale, fn ->
      new()
      |> from(from_address())
      |> to(to_string(subscription.user.email))
      |> bcc(record_copy_address())
      |> subject(~t"Your #{product} subscription is cancelled")
      |> text_body(
        Templates.subscription_cancelled(%{
          subscription: subscription,
          product: product,
          message: message,
          charged_on: charged_on,
          pickup?: subscription.fulfillment_option.fulfillment_method == :pickup,
          format_date: &Format.weekday_date(&1, subscription.locale)
        })
      )
    end)
  end

  defp subscription_price(subscription) do
    Decimal.add(subscription.product_variant.price, subscription.first_order_fulfillment_fee || 0)
  end

  @doc """
  Tells the customer their order was delivered. A collected order gets
  none: the customer was there. Expects `:customer_first_name` and
  `:recipient_first_name` loaded.
  """
  def order_delivered(order, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(delivered_subject(order))
      |> text_body(Templates.order_delivered(%{order: order, message: message}))
    end)
  end

  defp delivered_subject(%{gift: true, recipient_first_name: name}) when is_binary(name),
    do: ~t"Your order for #{recipient = name} has been delivered"

  defp delivered_subject(_order), do: ~t"Your Eden Flowers order has been delivered"

  @doc """
  Tells the customer nobody was home, with the photo of where the order was
  left, so they can go and look. Loads as `order_delivered/2`.
  """
  def order_left_at_door(order, photo_jpeg, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(left_at_door_subject(order))
      |> text_body(Templates.order_left_at_door(%{order: order, message: message}))
      |> attach_delivery_photo(photo_jpeg)
    end)
  end

  defp left_at_door_subject(%{gift: true, recipient_first_name: name}) when is_binary(name),
    do: ~t"Your order for #{recipient = name} was left at the door"

  defp left_at_door_subject(_order), do: ~t"Your Eden Flowers order was left at the door"

  defp attach_delivery_photo(email, photo_jpeg) do
    attachment(
      email,
      Swoosh.Attachment.new({:data, photo_jpeg}, filename: "eden-flowers-delivery.jpg", content_type: "image/jpeg")
    )
  end

  @doc """
  Tells the customer the shop cancelled their order or course booking, with
  Jennie's message and what was refunded. Expects it read with
  `:for_customer_email`. `money` holds what went back through Stripe
  (`refunded`) and what Jennie still hands back herself (`to_return`).
  """
  def cancelled(%Order{} = order, money) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers order for #{date = short_date(order)} is cancelled")
      |> text_body(
        Templates.order_cancelled(%{
          order: order,
          message: order.cancellation_reason,
          refunded: money.refunded,
          to_return: money.to_return,
          refunded_to: refunded_to(order.payments),
          format_currency: &Format.currency(&1, order.locale),
          format_date: &Format.weekday_date(&1, order.locale)
        })
      )
    end)
  end

  def cancelled(%CourseRegistration{} = registration, money) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"Your booking on #{course = registration.course.name} is cancelled")
      |> text_body(
        Templates.booking_cancelled(%{
          registration: registration,
          message: registration.cancellation_reason,
          refunded: money.refunded,
          to_return: money.to_return,
          refunded_to: refunded_to(registration.payments),
          format_date: &Format.weekday_date(&1, registration.locale),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

  @doc """
  Confirms an Online Order the customer cancelled in their account, and its
  refund, which always went back through Stripe. Matter-of-fact, from the
  shop. Loads as `cancelled/2`.
  """
  def cancellation_confirmed(%Order{} = order, money) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(automated_from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Order #{reference = order.order_reference} cancelled")
      |> text_body(
        Templates.cancellation_confirmed(%{
          order: order,
          refunded: money.refunded,
          refunded_to: refunded_to(order.payments),
          format_currency: &Format.currency(&1, order.locale),
          format_date: &Format.weekday_date(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  Tells the customer what Jennie refunded on their order or course booking,
  then her message. Expects it read with `:for_customer_email`. `refund`
  holds the `amount`, the `payment_method` it went back by, and her `note`.
  """
  def refunded(%Order{} = order, refund) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"A refund for your Eden Flowers order for #{date = short_date(order)}")
      |> text_body(
        Templates.order_refunded(%{
          order: order,
          refund: refund,
          refunded_to: refunded_how(refund.payment_method, order.payments),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  def refunded(%CourseRegistration{} = registration, refund) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"A refund for your booking on #{course = registration.course.name}")
      |> text_body(
        Templates.booking_refunded(%{
          registration: registration,
          refund: refund,
          refunded_to: refunded_how(refund.payment_method, registration.payments),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

  # Money Jennie handed back herself went the way she says; MobilePay to her
  # own number is a transfer, not a card refund, so it shows at once.
  defp refunded_how(:stripe, payments), do: refunded_to(payments)
  defp refunded_how(:mobilepay, _payments), do: :mobilepay_transfer
  defp refunded_how(method, _payments), do: method

  # Only Stripe payments are refunded here, almost always just one, so the
  # refund goes back the same way.
  defp refunded_to(payments) do
    paid_with =
      for payment <- payments, payment.method == :stripe, Decimal.positive?(payment.amount), uniq: true do
        {payment.payment_method_type, payment.card_brand, payment.card_last4}
      end

    case paid_with do
      [{"card", brand, last4}] when is_binary(brand) and is_binary(last4) -> {:card, String.capitalize(brand), last4}
      [{"mobilepay", _brand, _last4}] -> :mobilepay
      _mixed_or_unknown -> :unknown
    end
  end

  def course_confirmation(registration, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(course_confirmation_subject(registration))
      |> text_body(render_course_confirmation(registration, message))
    end)
  end

  # A payment link paid after the course sends the confirmation with the receipt.
  defp course_confirmation_subject(registration) do
    if course_over?(registration),
      do: ~t"Your booking on #{course = registration.course.name}",
      else: ~t"You're booked on #{course = registration.course.name}"
  end

  defp render_course_confirmation(registration, message) do
    Templates.course_confirmation(%{
      registration: registration,
      message: message,
      course_over?: course_over?(registration),
      format_date: &Format.weekday_date(&1, registration.locale),
      format_time: &Format.time(&1, registration.locale),
      format_currency: &Format.currency(&1, registration.locale)
    })
  end

  @doc """
  A link to pay a course booking awaiting payment, before or after the
  course. Paying confirms it. Expects `:course` translated, `:first_name`
  and `:balance` loaded.
  """
  def course_payment_link(registration, payment_link_url, message \\ nil) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"Pay for your booking on #{course = registration.course.name}")
      |> text_body(
        Templates.course_payment_link(%{
          registration: registration,
          message: message,
          payment_link_url: payment_link_url,
          course_over?: course_over?(registration),
          format_date: &Format.weekday_date(&1, registration.locale),
          format_time: &Format.time(&1, registration.locale),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

  defp course_over?(registration), do: Date.before?(registration.course.date, Edenflowers.ShopTime.today())

  @doc """
  A copy of a couple's wedding enquiry, bcc Jennie so she can reply to them
  directly. `enquiry` is the job args of `Edenflowers.WeddingEnquiry.SendEmails`.
  """
  def wedding_enquiry(%{"name" => name, "email" => email} = enquiry) do
    new()
    |> from(from_address())
    |> to({name, email})
    |> bcc(from_address())
    |> subject(~t"Your wedding enquiry to Eden Flowers")
    |> text_body(
      Templates.wedding_enquiry(%{
        enquiry: enquiry,
        first_name: Edenflowers.Accounts.Calculations.FirstName.extract(name),
        wedding_date: Format.weekday_date(enquiry["wedding_date"], enquiry["locale"])
      })
    )
  end

  @doc """
  Answers a newsletter signup. `signup` is `:new`, with a fresh welcome code;
  `:again_with_code`, from someone already subscribed whose code is still
  usable; or `:again`, whose code is used or expired, so `promo` is nil.
  """
  def newsletter(email_address, signup, promo, locale) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(newsletter_subject(signup))
    |> text_body(
      Templates.newsletter(%{
        signup: signup,
        promo_code: promo && promo.code,
        use_by: promo && Format.weekday_date(promo.expiration_date, locale),
        store_url: store_url()
      })
    )
  end

  defp newsletter_subject(:new), do: ~t"Your 15% welcome code for Eden Flowers"
  defp newsletter_subject(:again_with_code), do: ~t"Your Eden Flowers promo code"
  defp newsletter_subject(:again), do: ~t"Your Eden Flowers newsletter subscription"

  def error_alert(error) do
    new()
    |> from(automated_from_address())
    |> to(Application.fetch_env!(:edenflowers, :error_alert_email))
    |> subject("[Eden Flowers] #{String.slice(error.reason, 0, 80)}")
    |> text_body("""
    #{error.reason}

    Kind: #{error.kind}
    Where: #{error.source_function} (#{error.source_line})
    Last seen: #{error.last_occurrence_at}

    #{EdenflowersWeb.Endpoint.url()}/admin/errors/#{error.id}
    """)
  end

  @doc """
  Tells the shop's inbox what `Edenflowers.Orders.ShopNotice` says, in
  Swedish, Jennie's language. Just enough to notice it: the rest is a tap away.
  """
  def shop_notice(notice) do
    EdenflowersWeb.Gettext.with_app_locale("sv-FI", fn ->
      new()
      |> from(automated_from_address())
      |> to(Application.fetch_env!(:edenflowers, :shop_notice_email))
      |> subject(ShopNotice.title(notice, "sv-FI"))
      |> text_body("""
      #{shop_notice_time(notice)}#{~t"Open in the admin:"}
      #{EdenflowersWeb.Endpoint.url()}#{ShopNotice.path(notice)}
      """)
    end)
  end

  # Only a new order with a time or window says when: the title already says
  # the day, and a reminder's title the time.
  defp shop_notice_time({:new, %Edenflowers.Orders.Order{fulfillment_time_start: %Time{}} = order}) do
    "#{Format.weekday_date(order.fulfillment_date, "sv-FI")} #{Format.fulfillment_time(order, "sv-FI")}\n\n"
  end

  defp shop_notice_time(_notice), do: ""

  def otp_sign_in(email_address, otp_code) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(~t"#{otp_code} is your Eden Flowers sign-in code")
    |> text_body(Templates.otp_sign_in(%{otp_code: otp_code}))
  end

  def email_change_code(email_address, code) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(~t"#{code} is your email change code for Eden Flowers")
    |> text_body(Templates.email_change_code(%{code: code}))
  end

  defp account_url, do: EdenflowersWeb.Endpoint.url() <> "/account"

  # In the language the email is written in.
  defp store_url do
    {:ok, locale} = Localize.validate_locale(Gettext.get_locale(EdenflowersWeb.Gettext))
    EdenflowersWeb.LocalizedPaths.store_url(locale.cldr_locale_id)
  end

  defp from_address, do: Application.fetch_env!(:edenflowers, :mailer_from_address)

  # Copies Jennie keeps for the record but needn't act on. Fastmail delivers
  # info+copy@ to the info@ mailbox, where a rule files it out of the inbox.
  defp record_copy_address do
    {name, address} = from_address()
    [local, domain] = String.split(address, "@")
    {name, "#{local}+copy@#{domain}"}
  end

  defp automated_from_address do
    {_name, address} = from_address()
    {"Eden Flowers", address}
  end
end
