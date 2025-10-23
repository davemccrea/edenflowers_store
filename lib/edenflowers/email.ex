defmodule Edenflowers.Email do
  @moduledoc """
  Email templates and functions for sending emails
  """

  import Swoosh.Email

  @doc """
  Builds an order confirmation email
  """
  def order_confirmation(order) do
    new()
    |> from({"Eden Flowers", "orders@edenflowers.com"})
    |> to(order.customer_email)
    |> subject("Order Confirmation - #{order.order_reference}")
    |> text_body(render_order_confirmation(order))
  end

  defp render_order_confirmation(order) do
    EEx.eval_file(
      Path.join([__DIR__, "email", "templates", "order_confirmation.text.eex"]),
      order: order,
      format_currency: &format_currency/1,
      format_date: &format_date/1,
      format_datetime: &format_datetime/1
    )
  end

  defp format_currency(amount) do
    Cldr.Number.to_string!(amount, Edenflowers.Cldr, locale: "fi", currency: :EUR)
  end

  defp format_date(date) do
    Cldr.Date.to_string!(date, Edenflowers.Cldr, locale: "fi", format: :short)
  end

  defp format_datetime(datetime) do
    {:ok, date_part} = Cldr.Date.to_string(datetime, Edenflowers.Cldr, locale: "fi", format: :short)
    {:ok, time_part} = Cldr.Time.to_string(datetime, Edenflowers.Cldr, locale: "fi", format: :short)
    "#{date_part} #{time_part}"
  end
end
