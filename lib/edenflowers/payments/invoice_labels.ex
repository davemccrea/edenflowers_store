defmodule Edenflowers.Payments.InvoiceLabels do
  @moduledoc false

  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.ReceiptLabels

  # The invoice prints the receipt's lines, totals and VAT breakdown too, so
  # it gets the receipt's labels as well as its own.
  def for_locale(locale) do
    ReceiptLabels.for_locale(locale)
    |> Map.merge(own_labels(locale))
  end

  defp own_labels(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      %{
        "invoice" => dgettext("receipts", "Invoice"),
        "invoice-number" => dgettext("receipts", "Invoice number"),
        "invoice-date" => dgettext("receipts", "Invoice date"),
        "due-date" => dgettext("receipts", "Due date"),
        "your-reference" => your_reference(),
        "earlier" => dgettext("receipts", "Invoiced or paid earlier"),
        "paid" => paid(),
        "due-on-invoice" => dgettext("receipts", "Due on this invoice"),
        "payment-details" => dgettext("receipts", "Payment details"),
        "payee" => payee(),
        "iban" => dgettext("receipts", "Account (IBAN)"),
        "bic" => dgettext("receipts", "BIC"),
        "reference-number" => reference_number(),
        "amount" => amount(),
        "virtual-barcode" => virtual_barcode(),
        "use-reference" => dgettext("receipts", "Please use the reference number when you pay."),
        "late-interest" => late_interest()
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

  defp paid do
    gettext_comment("Money paid towards the order before this invoice, outside any earlier invoice.")
    dgettext("receipts", "Paid")
  end

  defp payee do
    gettext_comment("Who the bank transfer goes to, as on a Finnish credit transfer form (saaja).")
    dgettext("receipts", "Payee")
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

  defp late_interest do
    gettext_comment("The standard Finnish invoice line 'viivästyskorko korkolain mukaan' (Interest Act 633/1982).")
    dgettext("receipts", "Late payment interest according to the Interest Act.")
  end
end
