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
        "method-zervant" => dgettext("receipts", "Bank transfer"),
        "method-voucher" => dgettext("receipts", "Gift voucher"),
        "gift-voucher" => dgettext("receipts", "Gift voucher"),
        "valid-until" => dgettext("receipts", "Valid until"),
        # Translators: Before the name of the person a gift voucher is for, as "For: Mia".
        "voucher-for" => dgettext("receipts", "For"),
        "voucher-emailed" => dgettext("receipts", "Emailed to you as a PDF"),
        "voucher-collect" => dgettext("receipts", "Gift card to collect at Minimossen"),
        # Translators: Heading for the buyer's message printed on a gift voucher.
        "voucher-message" => dgettext("receipts", "Message on the voucher"),
        # Translators: Under the totals of a receipt for a gift voucher. A multi-purpose voucher is outside VAT
        # when sold (not taxed at 0 %): VAT is charged on what it buys.
        "vat-note-gift-voucher" =>
          dgettext("receipts", "A gift voucher is not subject to VAT. VAT is charged on what it's spent on.")
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
      # Translators: Closing line after handover or the course. "This" is the receipt,
      # which can also be downloaded rather than emailed.
      dgettext("receipts", "Questions? Just reply to the email this came with, or write to info@edenflowers.fi.")
    end)
  end
end
