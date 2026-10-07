defmodule Edenflowers.Email do
  @moduledoc """
  Builds the app's Swoosh email envelopes. Bodies are rendered by
  `Edenflowers.Email.Templates`; subjects are localised per the order's locale.
  """

  import Swoosh.Email
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Email.Templates
  alias Edenflowers.Format

  def order_confirmation(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> bcc(from_address())
      |> subject(~t"Your receipt for Eden Flowers order #{order.order_reference}")
      |> text_body(render_order_confirmation(order))
    end)
  end

  defp render_order_confirmation(order) do
    Templates.order_confirmation(%{
      order: order,
      format_date: &Format.date(&1, order.locale)
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
      |> bcc(from_address())
      |> subject(~t"Your Eden Flowers order #{order.order_reference}")
      |> text_body(
        Templates.order_details(%{
          order: order,
          payment_link_url: payment_link_url,
          format_date: &Format.weekday_date(&1, order.locale),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
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
      |> bcc(from_address())
      |> subject(~t"Payment needed for your Eden Flowers order #{order.order_reference}")
      |> text_body(
        Templates.payment_failed(%{
          order: order,
          payment_link_url: payment_link_url,
          format_date: &Format.weekday_date(&1, order.locale),
          format_currency: &Format.currency(&1, order.locale)
        })
      )
    end)
  end

  @doc """
  What a customer is sent once their Subscription is started: what comes and
  how often, the next date, and where to change it. The first delivery's
  receipt goes separately. Expects `:product_variant` and `user: [:first_name]` loaded.
  """
  def subscription_set_up(subscription) do
    EdenflowersWeb.Gettext.with_app_locale(subscription.locale, fn ->
      new()
      |> from(from_address())
      |> to(to_string(subscription.user.email))
      |> bcc(from_address())
      |> subject(~t"Your Eden Flowers subscription is set up")
      |> text_body(
        Templates.subscription_set_up(%{
          subscription: subscription,
          size: EdenflowersWeb.Admin.Components.variant_size_label(subscription.product_variant.size),
          interval: EdenflowersWeb.Checkout.Fields.interval_label(subscription.interval_weeks),
          account_url: EdenflowersWeb.Endpoint.url() <> "/account",
          format_date: &Format.weekday_date(&1, subscription.locale)
        })
      )
    end)
  end

  def order_delivered(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      new()
      |> from(from_address())
      |> to(order.customer_email)
      |> subject(~t"Your Eden Flowers order #{order.order_reference} has been delivered")
      |> text_body(Templates.order_delivered(%{order: order}))
    end)
  end

  def course_confirmation(registration) do
    EdenflowersWeb.Gettext.with_app_locale(registration.locale, fn ->
      new()
      |> from(from_address())
      |> to(registration.email)
      |> bcc(from_address())
      |> subject(~t"You're booked: #{course = registration.course.name}")
      |> text_body(render_course_confirmation(registration))
    end)
  end

  defp render_course_confirmation(registration) do
    Templates.course_confirmation(%{
      registration: registration,
      format_date: &Format.weekday_numeric_date(&1, registration.locale),
      format_time: &Format.time(&1, registration.locale)
    })
  end

  def newsletter_promo(email_address, promo_code) do
    new()
    |> from(from_address())
    |> to(email_address)
    |> subject(~t"Welcome to Eden Flowers: your 15% off code inside")
    |> text_body(Templates.newsletter_promo(%{promo_code: promo_code}))
  end

  def newsletter_already_subscribed(email_address, promo_code) do
    new()
    |> from(from_address())
    |> to(email_address)
    |> subject(~t"Your Eden Flowers promo code")
    |> text_body(Templates.newsletter_already_subscribed(%{promo_code: promo_code}))
  end

  def newsletter_resubscribed(email_address) do
    new()
    |> from(from_address())
    |> to(email_address)
    |> subject(~t"Welcome back to the Eden Flowers newsletter")
    |> text_body(Templates.newsletter_resubscribed(%{}))
  end

  def error_alert(error) do
    new()
    |> from(from_address())
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

  def otp_sign_in(email_address, otp_code) do
    new()
    |> from(from_address())
    |> to(email_address)
    |> subject(~t"Your Eden Flowers sign-in code")
    |> text_body(Templates.otp_sign_in(%{otp_code: otp_code}))
  end

  def email_change_code(email_address, code) do
    new()
    |> from(from_address())
    |> to(email_address)
    |> subject(~t"Confirm your new Eden Flowers email")
    |> text_body(Templates.email_change_code(%{code: code}))
  end

  defp from_address, do: Application.fetch_env!(:edenflowers, :mailer_from_address)
end
