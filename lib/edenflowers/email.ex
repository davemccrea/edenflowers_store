defmodule Edenflowers.Email do
  @moduledoc """
  Email templates and functions for sending emails
  """

  import Swoosh.Email
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Email.Templates
  alias Edenflowers.Localize.Format

  @from_address Application.compile_env!(:edenflowers, :mailer_from_address)

  @doc """
  Builds an order confirmation email
  """
  def order_confirmation(order) do
    Gettext.with_locale(EdenflowersWeb.Gettext, order.locale, fn ->
      new()
      |> from(@from_address)
      |> to(order.customer_email)
      |> subject("#{~t"Order Confirmation"} - #{order.order_reference}")
      |> text_body(render_order_confirmation(order, order.locale))
    end)
  end

  defp render_order_confirmation(order, locale) do
    Templates.order_confirmation(%{
      order: order,
      format_currency: &Format.currency(&1, locale),
      format_date: &Format.date(&1, locale),
      format_datetime: &Format.datetime(&1, locale)
    })
  end

  def newsletter_promo(email_address, promo_code) do
    new()
    |> from(@from_address)
    |> to(email_address)
    |> subject(~t"Welcome to Eden Flowers — your 15% off code inside")
    |> text_body(Templates.newsletter_promo(%{promo_code: promo_code}))
  end

  def newsletter_already_subscribed(email_address, promo_code) do
    new()
    |> from(@from_address)
    |> to(email_address)
    |> subject(~t"Your Eden Flowers promo code")
    |> text_body(Templates.newsletter_already_subscribed(%{promo_code: promo_code}))
  end

  def newsletter_resubscribed(email_address) do
    new()
    |> from(@from_address)
    |> to(email_address)
    |> subject(~t"Welcome back to the Eden Flowers newsletter")
    |> text_body(Templates.newsletter_resubscribed(%{}))
  end

  def otp_sign_in(email_address, otp_code) do
    new()
    |> from(@from_address)
    |> to(email_address)
    |> subject(~t"Your Eden Flowers sign-in code")
    |> text_body(Templates.otp_sign_in(%{otp_code: otp_code}))
  end
end
