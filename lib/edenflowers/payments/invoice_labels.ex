defmodule Edenflowers.Payments.InvoiceLabels do
  @moduledoc false

  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.ReceiptLabels

  # Shared table and seller labels keep invoice and receipt typography consistent.
  def for_locale(locale) do
    ReceiptLabels.for_locale(locale)
    |> Map.merge(own_labels(locale))
  end

  defp own_labels(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      %{
        "unit-price-incl-vat" => dgettext("receipts", "Unit price incl. VAT"),
        "invoice" => dgettext("receipts", "Invoice"),
        "invoice-number" => dgettext("receipts", "Invoice number"),
        "invoice-date" => dgettext("receipts", "Invoice date"),
        "due-date" => dgettext("receipts", "Due date"),
        "supply-date" => dgettext("receipts", "Date of supply"),
        "your-reference" => your_reference(),
        "due-on-invoice" => dgettext("receipts", "Due on this invoice"),
        "paid" => dgettext("receipts", "Paid"),
        "left-to-pay" => dgettext("receipts", "Still to pay"),
        "payment-details" => dgettext("receipts", "Payment details"),
        "iban" => dgettext("receipts", "Account (IBAN)"),
        "reference-number" => reference_number(),
        "amount" => amount(),
        "virtual-barcode" => virtual_barcode(),
        "late-interest" => late_interest(),
        "credit-note" => dgettext("receipts", "Credit note"),
        "credit-note-number" => dgettext("receipts", "Credit note number"),
        "credit-date" => dgettext("receipts", "Date"),
        "reason" => reason(),
        "credited" => credited()
      }
    end)
  end

  # One function per commented label: gettext_comment/1 attaches to the next
  # message extracted, so it has to be a statement of its own.

  defp your_reference do
    gettext_comment(
      "The buying company's own reference for the purchase, such as a purchase order number (viitteenne)."
    )

    dgettext("receipts", "Your reference")
  end

  defp reference_number do
    gettext_comment("The Finnish viitenumero the payer types into their bank, not the order reference.")
    dgettext("receipts", "Reference number")
  end

  defp amount do
    gettext_comment("The sum to transfer, as a field of the payment details.")
    dgettext("receipts", "Amount")
  end

  defp virtual_barcode do
    gettext_comment("The 54-digit virtuaaliviivakoodi a payer can paste into their bank instead of typing the details.")
    dgettext("receipts", "Virtual barcode")
  end

  defp reason do
    gettext_comment("Why Jennie cancelled the invoice, as she wrote it.")
    dgettext("receipts", "Reason")
  end

  defp credited do
    gettext_comment("The total a credit note takes off, printed as a negative amount (hyvitetään).")
    dgettext("receipts", "Credited")
  end

  defp late_interest do
    gettext_comment(
      "The yearly interest charged on a late payment (viivästyskorko), printed beside a rate such as 8,00 %."
    )

    dgettext("receipts", "Late payment interest")
  end
end
