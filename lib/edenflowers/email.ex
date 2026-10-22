defmodule Edenflowers.Email do
  @moduledoc """
  Builds the app's Swoosh email envelopes. Bodies are rendered by
  `Edenflowers.Email.Templates`; subjects are localised per the order's locale.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  import Swoosh.Email

  alias Edenflowers.Email.Templates
  alias Edenflowers.Format
  alias Edenflowers.Orders.ShopNotice

  def order_confirmation(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your receipt for Eden Flowers order #{order.order_reference}")
      |> text_body(render_order_confirmation(order))
    end)
  end

  defp render_order_confirmation(order) do
    Templates.order_confirmation(%{
      order: order,
      format_date: &Format.weekday_date(&1, order.locale),
      fulfillment_on: fulfillment_on(order),
      account_url: account_url()
    })
  end

  @doc """
  What a custom order's customer is sent when Jennie places it: the order as
  agreed and how to pay. No receipt, because nothing has been paid yet.
  Sent again after an edit, it shows the order as it now stands rather than
  what changed, since the customer pays against the whole. Expects `line_items: [:subtotal]` and `:grand_total` loaded.
  """
  def order_details(order, payment_link_url) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers order #{order.order_reference}")
      |> text_body(
        Templates.order_details(%{
          order: order,
          payment_link_url: payment_link_url,
          fulfillment_on: fulfillment_on(order),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

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
  What a subscriber is sent when the card saved for their subscription is
  refused for an Occurrence: the delivery still happens, and the payment link
  pays for it. Expects `:customer_first_name` and `:grand_total` loaded.
  """
  def payment_failed(order, payment_link_url) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Payment needed for your Eden Flowers order #{order.order_reference}")
      |> text_body(
        Templates.payment_failed(%{
          order: order,
          payment_link_url: payment_link_url,
          account_url: account_url(),
          format_date: &Format.weekday_date(&1, order.locale),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  What a customer is sent once their Subscription is started: what comes and
  how often, what each costs, the first two dates, and where to change it.
  The first order's receipt goes separately. Expects `:product_variant`,
  `:fulfillment_option`, `:first_delivery_date`, `:first_order_fulfillment_fee`
  and `user: [:first_name]` loaded.
  """
  def subscription_set_up(subscription) do
    EdenflowersWeb.Gettext.with_app_locale(subscription.locale, fn ->
      new()
      |> from(from_address())
      |> to(to_string(subscription.user.email))
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers subscription is set up")
      |> text_body(
        Templates.subscription_set_up(%{
          subscription: subscription,
          pickup?: subscription.fulfillment_option.fulfillment_method == :pickup,
          size: EdenflowersWeb.Admin.Components.variant_size_label(subscription.product_variant.size),
          interval: EdenflowersWeb.Checkout.Fields.interval_label(subscription.interval_weeks),
          price: Format.currency(subscription_price(subscription), subscription.locale),
          charge_days: Edenflowers.Orders.Subscription.lead_days(),
          account_url: account_url(),
          format_date: &Format.weekday_date(&1, subscription.locale)
        })
      )
    end)
  end

  defp subscription_price(subscription) do
    Decimal.add(subscription.product_variant.price, subscription.first_order_fulfillment_fee || 0)
  end

  def order_fulfilled(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      subject =
        if order.fulfillment_method == :pickup,
          do: ~t"Your Eden Flowers order #{order.order_reference} has been collected",
          else: ~t"Your Eden Flowers order #{order.order_reference} has been delivered"

      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(subject)
      |> text_body(Templates.order_fulfilled(%{order: order}))
    end)
  end

  def order_left_at_door(order, photo_jpeg) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"Your Eden Flowers order #{order.order_reference} has been delivered (photo attached)")
      |> text_body(Templates.order_left_at_door(%{order: order}))
      |> attachment(
        Swoosh.Attachment.new({:data, photo_jpeg}, filename: "eden-flowers-delivery.jpg", content_type: "image/jpeg")
      )
    end)
  end

  @doc """
  Expects `:payments` loaded, to say where the refund went. `money` holds what
  went back through Stripe (`refunded`) and what Jennie still hands back
  herself (`to_return`).
  """
  def order_cancelled(order, money, cancelled_by) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(from_address())
      |> subject(~t"Your Eden Flowers order #{order.order_reference} is cancelled")
      |> text_body(
        Templates.order_cancelled(%{
          order: order,
          refunded: money.refunded,
          to_return: money.to_return,
          refunded_to: refunded_to(order.payments),
          cancelled_by: cancelled_by,
          format_currency: &Format.currency(&1, order.locale),
          format_date: &Format.date(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  Tells the customer what Jennie refunded on their order, and why. Expects
  `:customer_first_name` and `:payments` loaded. `refund` holds the
  `amount`, the `payment_method` it went back by, and Jennie's `note`.
  """
  def order_refunded(order, refund) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(record_copy_address())
      |> subject(~t"A refund for your Eden Flowers order #{order.order_reference}")
      |> text_body(
        Templates.order_refunded(%{
          order: order,
          refund: refund,
          refunded_to: refunded_to(order.payments),
          format_currency: &Format.currency(&1, order.locale),
          format_date: &Format.date(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  Tells the customer what Jennie refunded on their course booking, and why.
  Expects `:course` translated, `:first_name` and `:payments` loaded.
  """
  def booking_refunded(registration, refund) do
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
          refunded_to: refunded_to(registration.payments),
          format_currency: &Format.currency(&1, registration.locale),
          format_date: &Format.weekday_date(&1, registration.locale)
        })
      )
    end)
  end

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

  def course_confirmation(registration, payment_link_url) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"You're booked on #{course = registration.course.name}")
      |> text_body(render_course_confirmation(registration, payment_link_url))
    end)
  end

  defp render_course_confirmation(registration, payment_link_url) do
    Templates.course_confirmation(%{
      registration: registration,
      payment_link_url: payment_link_url,
      format_date: &Format.weekday_date(&1, registration.locale),
      format_time: &Format.time(&1, registration.locale),
      format_currency: &Format.currency(&1, registration.locale)
    })
  end

  @doc """
  Tells the customer Jennie cancelled their booking, and what was refunded.
  Expects `:course` translated, `:first_name` and `:payments` loaded. `money`
  holds what went back through Stripe (`refunded`) and what Jennie still
  hands back herself (`to_return`).
  """
  def booking_cancelled(registration, money) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"Your booking on #{course = registration.course.name} is cancelled")
      |> text_body(
        Templates.booking_cancelled(%{
          registration: registration,
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
  A link to pay a course booking online, for what it still owes. Expects
  `:course` translated, `:first_name` and `:balance` loaded.
  """
  def course_payment_link(registration, payment_link_url) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(record_copy_address())
      |> subject(~t"Pay for your booking on #{course = registration.course.name}")
      |> text_body(
        Templates.course_payment_link(%{
          registration: registration,
          payment_link_url: payment_link_url,
          format_date: &Format.weekday_date(&1, registration.locale),
          format_time: &Format.time(&1, registration.locale),
          format_currency: &Format.currency(&1, registration.locale)
        })
      )
    end)
  end

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

  def newsletter_promo(email_address, promo, locale) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(~t"Your 15% welcome code for Eden Flowers")
    |> text_body(
      Templates.newsletter_promo(%{promo_code: promo.code, use_by: use_by(promo, locale), store_url: store_url()})
    )
  end

  def newsletter_already_subscribed(email_address, promo, locale) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(~t"Your Eden Flowers promo code")
    |> text_body(
      Templates.newsletter_already_subscribed(%{
        promo_code: promo.code,
        use_by: use_by(promo, locale),
        store_url: store_url()
      })
    )
  end

  defp use_by(promo, locale), do: Format.weekday_date(promo.expiration_date, locale)

  def newsletter_resubscribed(email_address) do
    new()
    |> from(automated_from_address())
    |> to(email_address)
    |> subject(~t"Your Eden Flowers newsletter subscription")
    |> text_body(Templates.newsletter_resubscribed(%{shop_url: store_url()}))
  end

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
