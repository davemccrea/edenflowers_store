defmodule Edenflowers.Payments.InvoicePdf do
  @moduledoc "Renders immutable standalone invoice content and full reversals of its frozen financial snapshot."

  alias Edenflowers.Format
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceLabels
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.Payments.VirtualBarcode
  alias Edenflowers.Typst

  def filename(%Invoice{number: number, locale: locale}), do: "#{document_name(:invoice, locale)}-#{number}.pdf"

  def filename(%CreditNote{number: number, invoice: %Invoice{locale: locale}}),
    do: "#{document_name(:credit_note, locale)}-#{number}.pdf"

  defp document_name(:invoice, "fi"), do: "lasku"
  defp document_name(:invoice, locale) when locale in ["sv", "sv-FI"], do: "faktura"
  defp document_name(:invoice, _), do: "invoice"
  defp document_name(:credit_note, "fi"), do: "hyvityslasku"
  defp document_name(:credit_note, locale) when locale in ["sv", "sv-FI"], do: "kreditnota"
  defp document_name(:credit_note, _), do: "credit-note"

  def attachment(pdf, document),
    do: Swoosh.Attachment.new({:data, pdf}, filename: filename(document), content_type: "application/pdf")

  def generate(%Invoice{issued_at: nil}), do: {:error, :draft_invoice}

  def generate(%Invoice{content: content} = invoice) when is_map(content),
    do: Typst.render("invoice-main.typ", "invoice", payload(invoice))

  def generate(%CreditNote{} = note) do
    with {:ok, note} <- Ash.load(note, :invoice, authorize?: false) do
      Typst.render("credit-note-main.typ", "credit_note", build_payload(note))
    end
  end

  def payload(%Invoice{content: content, locale: locale}),
    do: Map.put(content, "labels", InvoiceLabels.for_locale(locale))

  def content(%Invoice{} = invoice), do: {:ok, invoice |> build_payload() |> Jason.encode!() |> Jason.decode!()}

  def build_payload(%Invoice{} = invoice) do
    locale = invoice.locale
    seller = Map.new(invoice.seller_snapshot, fn {key, value} -> {to_string(key), value} end)

    %{
      lang: language(locale),
      number: invoice.number,
      invoice_date: Format.date(invoice.invoice_date, locale),
      due_date: Format.date(invoice.due_date, locale),
      supply_date: if(invoice.supply_date, do: Format.date(invoice.supply_date, locale)),
      supply_description: invoice.supply_description,
      late_interest_rate: percent(seller["late_interest_rate"], locale),
      customer_reference: invoice.customer_reference,
      seller: Map.take(seller, ["name", "business_id", "address", "iban"]),
      buyer: buyer(invoice),
      line_items: lines(invoice.financial_snapshot, locale),
      vat_breakdown: vat_rows(invoice.financial_snapshot, locale),
      amount: Format.currency(invoice.amount, locale),
      reference_number: ReferenceNumber.format(invoice.reference_number),
      virtual_barcode:
        VirtualBarcode.version_4(seller["iban"], invoice.amount, invoice.reference_number, invoice.due_date)
    }
  end

  def build_payload(%CreditNote{invoice: %Invoice{} = invoice} = note) do
    content = invoice.content
    locale = invoice.locale

    %{
      lang: language(locale),
      labels: InvoiceLabels.for_locale(locale),
      number: note.number,
      credit_date: Format.date(note.credit_date, locale),
      invoice_number: invoice.number,
      invoice_date: content["invoice_date"],
      customer_reference: content["customer_reference"],
      reason: note.reason,
      seller: Map.take(content["seller"], ["name", "business_id", "address"]),
      buyer: content["buyer"],
      line_items: lines(invoice.financial_snapshot, locale, true),
      vat_breakdown: vat_rows(invoice.financial_snapshot, locale, true),
      amount: money(invoice.financial_snapshot["gross"], locale, true)
    }
  end

  defp lines(snapshot, locale, negative? \\ false) do
    Enum.map(snapshot["lines"], fn line ->
      %{
        product_name: line["description"],
        variant_size: nil,
        quantity: line["quantity"],
        unit_price_ex_tax: unit_price(line["unit_price"], locale, negative?),
        tax_rate: percent(Decimal.div(decimal(line["vat_rate"]), 100), locale),
        total: money(line["gross"], locale, negative?)
      }
    end)
  end

  # Preserve the supplied VAT-inclusive unit price precision; extended gross is rounded only once per line.
  defp unit_price(value, _locale, negative?) do
    value = decimal(value)
    digits = max(2, -value.exp)

    Localize.Number.to_string!(if(negative?, do: Decimal.negate(value), else: value),
      locale: "fi",
      currency: :EUR,
      fractional_digits: digits
    )
  end

  defp vat_rows(snapshot, locale, negative? \\ false) do
    Enum.map(snapshot["vat_breakdown"], fn row ->
      %{
        rate: percent(Decimal.div(decimal(row["rate"]), 100), locale),
        base: money(row["base"], locale, negative?),
        tax: money(row["vat"], locale, negative?),
        gross: money(row["gross"], locale, negative?)
      }
    end)
  end

  defp buyer(%Invoice{business_customer: true} = invoice),
    do: %{
      company_name: invoice.company_name,
      business_id: invoice.business_id,
      name: invoice.buyer_name,
      address: invoice.billing_address
    }

  defp buyer(invoice),
    do: %{company_name: nil, business_id: nil, name: invoice.buyer_name, address: invoice.buyer_address}

  defp language("sv-FI"), do: "sv"
  defp language("en-GB"), do: "en"
  defp language(locale), do: locale
  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

  defp money(value, locale, negative?),
    do: Format.currency(if(negative?, do: Decimal.negate(decimal(value)), else: decimal(value)), locale)

  defp percent(value, locale),
    do: Localize.Number.to_string!(decimal(value), locale: locale, format: :percent, fractional_digits: 2)
end
