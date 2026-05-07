defmodule Edenflowers.Email do
  @moduledoc """
  Email templates and functions for sending emails
  """

  import Swoosh.Email
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require EEx

  @from_address {"Eden Flowers", "info@edenflowers.fi"}

  # Compile the template at compile-time so gettext extraction works
  EEx.function_from_file(
    :defp,
    :render_order_confirmation_template,
    Path.join([__DIR__, "email", "templates", "order_confirmation.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(
    :defp,
    :render_newsletter_promo_template,
    Path.join([__DIR__, "email", "templates", "newsletter_promo.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(
    :defp,
    :render_newsletter_already_subscribed_template,
    Path.join([__DIR__, "email", "templates", "newsletter_already_subscribed.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(
    :defp,
    :render_newsletter_resubscribed_template,
    Path.join([__DIR__, "email", "templates", "newsletter_resubscribed.text.eex"]),
    [:_assigns]
  )

  @doc """
  Builds an order confirmation email
  """
  def order_confirmation(order) do
    Gettext.put_locale(EdenflowersWeb.Gettext, order.locale)

    new()
    |> from(@from_address)
    |> to(order.customer_email)
    |> subject("#{~t"Order Confirmation"} - #{order.order_reference}")
    |> text_body(render_order_confirmation(order, order.locale))
  end

  defp render_order_confirmation(order, locale) do
    assigns = %{
      order: order,
      format_currency: &format_currency(&1, locale),
      format_date: &format_date(&1, locale),
      format_datetime: &format_datetime(&1, locale)
    }

    render_order_confirmation_template(assigns)
  end

  def newsletter_promo(email_address, promo_code) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(email_address)
    |> subject(~t"Welcome to Eden Flowers — your 15% off code inside")
    |> text_body(render_newsletter_promo_template(%{promo_code: promo_code}))
  end

  def newsletter_already_subscribed(email_address, promo_code) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(email_address)
    |> subject(~t"Your Eden Flowers promo code")
    |> text_body(render_newsletter_already_subscribed_template(%{promo_code: promo_code}))
  end

  def newsletter_resubscribed(email_address) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(email_address)
    |> subject(~t"Welcome back to the Eden Flowers newsletter")
    |> text_body(render_newsletter_resubscribed_template(%{}))
  end

  defp format_currency(amount, locale) do
    Localize.Number.to_string!(amount, locale: locale, currency: :EUR)
  end

  defp format_date(date, locale) do
    Localize.Date.to_string!(date, locale: locale, format: :short)
  end

  defp format_datetime(datetime, locale) do
    {:ok, date_part} = Localize.Date.to_string(datetime, locale: locale, format: :short)
    {:ok, time_part} = Localize.Time.to_string(datetime, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end
end
