defmodule Edenflowers.Orders.ReceiptLabels do
  @moduledoc false

  use Gettext, backend: EdenflowersWeb.Gettext

  def for_locale(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      %{
        "receipt" => dgettext("receipts", "Receipt"),
        "reference" => dgettext("receipts", "Reference"),
        "order-date" => dgettext("receipts", "Order date"),
        "delivery-date" => dgettext("receipts", "Delivery date"),
        "pickup-date" => dgettext("receipts", "Pickup date"),
        "business-id" => dgettext("receipts", "Business ID"),
        "customer" => dgettext("receipts", "Customer"),
        "delivery" => dgettext("receipts", "Delivery"),
        "pickup" => dgettext("receipts", "Pickup"),
        "course" => dgettext("receipts", "Course"),
        "course-date" => dgettext("receipts", "Date"),
        "card-message" => dgettext("receipts", "Card message"),
        "order" => dgettext("receipts", "Order"),
        "item" => dgettext("receipts", "Item"),
        "unit-price-excl-vat" => dgettext("receipts", "Unit price net"),
        # Translators: Abbreviated quantity column heading in the receipt PDF.
        "quantity" => dgettext("receipts", "Qty"),
        "vat" => dgettext("receipts", "VAT"),
        "total" => dgettext("receipts", "Total"),
        "subtotal" => dgettext("receipts", "Subtotal"),
        "vat-rate" => dgettext("receipts", "VAT rate"),
        "vat-breakdown" => dgettext("receipts", "VAT breakdown"),
        "net" => dgettext("receipts", "Net"),
        "gross" => dgettext("receipts", "Gross"),
        "delivery-fee" => dgettext("receipts", "Delivery fee"),
        "pickup-fee" => dgettext("receipts", "Pickup fee"),
        "discount" => dgettext("receipts", "Discount"),
        "total-paid" => dgettext("receipts", "Order total"),
        "thank-you" => dgettext("receipts", "Thank you for your order"),
        "method-card" => dgettext("receipts", "Card"),
        "method-zettle" => dgettext("receipts", "Card"),
        "method-mobilepay" => dgettext("receipts", "MobilePay"),
        "method-klarna" => dgettext("receipts", "Klarna"),
        "method-cash" => dgettext("receipts", "Cash"),
        "method-zervant" => dgettext("receipts", "Bank transfer")
      }
    end)
  end

  @doc """
  The receipt's labels, closing on how to reach Jennie. Changes are only
  offered while the order or course is still to come. After that the receipt
  may come with any email, or be downloaded, so the line names the shop's
  address too.
  """
  def for_receipt(locale, upcoming?) do
    locale |> for_locale() |> Map.put("closing-line", closing_line(locale, upcoming?))
  end

  defp closing_line(locale, true = _upcoming?) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      dgettext("receipts", "Questions or changes? Reply to your confirmation email and Jennie will get back to you.")
    end)
  end

  defp closing_line(locale, false = _upcoming?) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      # Translators: The receipt's closing line once the order is handed over or the course held. "This" is the receipt, which can also be downloaded rather than emailed.
      dgettext("receipts", "Questions? Just reply to the email this came with, or write to info@edenflowers.fi.")
    end)
  end

  @doc "How a payment against an invoice reads on the receipt."
  def invoice_payment(number, locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      # Translators: A payment row on the receipt, naming the invoice it paid so a company can match them. %{number} is the invoice number, e.g. 1338.
      dgettext("receipts", "Bank transfer, invoice %{number}", number: number)
    end)
  end
end
