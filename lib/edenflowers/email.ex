defmodule Edenflowers.Email do
  @moduledoc """
  Email templates and functions for sending emails
  """

  import Swoosh.Email
  use Gettext, backend: EdenflowersWeb.Gettext

  require EEx

  # Compile the template at compile-time so gettext extraction works
  EEx.function_from_file(
    :defp,
    :render_order_confirmation_template,
    Path.join([__DIR__, "email", "templates", "order_confirmation.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(:defp, :render_newsletter_promo_template,
    Path.join([__DIR__, "email", "templates", "newsletter_promo.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(:defp, :render_newsletter_already_subscribed_template,
    Path.join([__DIR__, "email", "templates", "newsletter_already_subscribed.text.eex"]),
    [:assigns]
  )

  EEx.function_from_file(:defp, :render_newsletter_resubscribed_template,
    Path.join([__DIR__, "email", "templates", "newsletter_resubscribed.text.eex"]),
    [:assigns]
  )

  @doc """
  Builds an order confirmation email
  """
  def order_confirmation(order) do
    Gettext.put_locale(EdenflowersWeb.Gettext, order.locale)

    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(order.customer_email)
    |> subject("#{gettext("Order Confirmation")} - #{order.order_reference}")
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
    |> subject(gettext("Welcome to Eden Flowers — your 15% off code inside"))
    |> text_body(render_newsletter_promo_template(%{promo_code: promo_code}))
  end

  def newsletter_already_subscribed(email_address, promo_code) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(email_address)
    |> subject(gettext("Your Eden Flowers promo code"))
    |> text_body(render_newsletter_already_subscribed_template(%{promo_code: promo_code}))
  end

  def newsletter_resubscribed(email_address) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(email_address)
    |> subject(gettext("Welcome back to the Eden Flowers newsletter"))
    |> text_body(render_newsletter_resubscribed_template(%{}))
  end

  defp format_currency(amount, locale) do
    Cldr.Number.to_string!(amount, Edenflowers.Cldr, locale: locale, currency: :EUR)
  end

  defp format_date(date, locale) do
    Cldr.Date.to_string!(date, Edenflowers.Cldr, locale: locale, format: :short)
  end

  defp format_datetime(datetime, locale) do
    {:ok, date_part} = Cldr.Date.to_string(datetime, Edenflowers.Cldr, locale: locale, format: :short)
    {:ok, time_part} = Cldr.Time.to_string(datetime, Edenflowers.Cldr, locale: locale, format: :short)
    "#{date_part} #{time_part}"
  end
end
