defmodule Edenflowers.Email do
  @moduledoc """
  Email templates and builders for the application.
  """

  import Swoosh.Email

  require EEx

  @from_address {"Jennie", "info@edenflowers.fi"}

  # Compile templates at compile-time
  @template_dir Path.join([__DIR__, "email", "templates"])

  EEx.function_from_file(
    :defp,
    :render_order_confirmation,
    Path.join(@template_dir, "order_confirmation.text.eex"),
    [:assigns]
  )

  @doc """
  Builds an order confirmation email.

  The order must be loaded with all necessary associations and calculations:
  - `:line_items` (relationship)
  - `:fulfillment_option` (relationship)
  - `:line_total` (aggregate)
  - `:line_tax_amount` (aggregate)
  - `:discount_amount` (aggregate)
  - `:tax_amount` (calculation)
  - `:total` (calculation)
  - `:order_reference` (calculation)

  Use `Order.get_for_checkout!/1` or ensure the order is properly loaded before calling this function.
  """
  def order_confirmation(order) do
    new()
    |> to({order.customer_name, order.customer_email})
    |> from(@from_address)
    |> subject("Thank you for your order")
    |> text_body(render_order_confirmation_email(order))
  end

  defp render_order_confirmation_email(order) do
    assigns = %{
      order: order,
      format_currency: &format_currency/1,
      format_datetime: &format_datetime/1,
      format_date: &format_date/1,
      humanize_fulfillment_method: &humanize_fulfillment_method/1
    }

    order
    |> then(fn _ -> assigns end)
    |> render_order_confirmation()
    |> String.trim_trailing()
  end

  # Helper functions for templates

  defp format_currency(nil), do: "€0.00"

  defp format_currency(amount) do
    Edenflowers.Cldr.Number.to_string!(amount, currency: :EUR)
  end

  defp format_datetime(datetime) do
    Edenflowers.Cldr.DateTime.to_string!(datetime, format: :long)
  end

  defp format_date(date) do
    Edenflowers.Cldr.Date.to_string!(date, format: :long)
  end

  defp humanize_fulfillment_method(:delivery), do: "Delivery"
  defp humanize_fulfillment_method(:pickup), do: "Pickup"
  defp humanize_fulfillment_method(_), do: "Unknown"
end
