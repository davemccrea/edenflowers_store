defmodule Edenflowers.Payments.InvoicePdf do
  @moduledoc """
  Renders an Invoice's PDF with Typst (`priv/receipts/invoice.typ`), for an
  order or a Course booking alike.

  The buyer, number, dates and amount come from the invoice's frozen
  columns. The purchase's lines, totals and VAT per rate are the receipt's
  (`Orders.Receipt.build_payload/1`), so the two documents never disagree.
  Before them it lists what the purchase was already invoiced or paid, and
  after them what is due on this invoice, with the bank details, viitenumero
  and virtual barcode to pay it with.
  """

  alias Edenflowers.Format
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceLabels
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.Payments.VirtualBarcode
  alias Edenflowers.Typst

  @receipt_keys [
    :lang,
    :order_reference,
    :fulfillment_method,
    :fulfillment_date,
    :line_items,
    :items_subtotal,
    :fulfillment_fee,
    :discount,
    :vat_breakdown,
    :grand_total
  ]

  @doc "The PDF's file name in the invoice's language, as `lasku-1001.pdf`, `faktura-1001.pdf` or `invoice-1001.pdf`."
  def filename(%Invoice{number: number, locale: locale}), do: "#{document_name(locale)}-#{number}.pdf"

  defp document_name("fi"), do: "lasku"
  defp document_name("sv-FI"), do: "faktura"
  defp document_name(_english), do: "invoice"

  @doc "The PDF as an email attachment, named by `filename/1`."
  def attachment(pdf, invoice) do
    Swoosh.Attachment.new({:data, pdf}, filename: filename(invoice), content_type: "application/pdf")
  end

  def generate(%Invoice{} = invoice) do
    with {:ok, invoice} <- load(invoice) do
      Typst.render("invoice-main.typ", "invoice", build_payload(invoice))
    end
  end

  @doc "Loads the purchase, its receipt data, invoices and payments, which `build_payload/1` expects."
  def load(invoice) do
    Ash.load(
      invoice,
      [
        order: [:invoices | Receipt.order_load()],
        course_registration: [:course, :payments, :invoices]
      ],
      authorize?: false
    )
  end

  # Exposed so payload serialization can be tested without invoking Typst.
  def build_payload(%Invoice{} = invoice) do
    locale = invoice.locale
    purchase = invoice.order || invoice.course_registration
    seller = seller(invoice)

    # In the invoice's language, which Jennie may have changed from the purchase's.
    %{purchase | locale: locale}
    |> Receipt.build_payload()
    |> Map.take(@receipt_keys)
    |> Map.merge(%{
      labels: InvoiceLabels.for_locale(locale),
      number: invoice.number,
      invoice_date: Format.date(invoice.invoice_date, locale),
      due_date: Format.date(invoice.due_date, locale),
      customer_reference: invoice.customer_reference,
      seller: Map.take(seller, [:name, :business_id, :address, :iban, :bic]),
      buyer: buyer(invoice),
      earlier_invoices: earlier_invoices(invoice, purchase.invoices, locale),
      paid_earlier: paid_earlier(invoice, purchase.payments, locale),
      amount: Format.currency(invoice.amount, locale),
      reference_number: ReferenceNumber.format(invoice.reference_number),
      virtual_barcode: VirtualBarcode.version_4(seller.iban, invoice.amount, invoice.reference_number, invoice.due_date)
    })
  end

  # The one place the seller is read, so that freezing the seller details
  # onto each invoice would only change this.
  defp seller(_invoice), do: Invoice.seller()

  defp buyer(%Invoice{business_customer: true} = invoice) do
    %{
      company_name: invoice.company_name,
      business_id: invoice.business_id,
      name: invoice.buyer_name,
      address: invoice.billing_address,
      email: invoice.buyer_email
    }
  end

  defp buyer(invoice) do
    %{
      company_name: nil,
      business_id: nil,
      name: invoice.buyer_name,
      address: invoice.buyer_address,
      email: invoice.buyer_email
    }
  end

  # Invoices are numbered in the order they were made, and never change, so
  # the earlier ones read the same however late this one is rendered.
  defp earlier_invoices(invoice, invoices, locale) do
    for earlier <- Enum.sort_by(invoices, & &1.number), earlier.number < invoice.number do
      %{
        number: earlier.number,
        invoice_date: Format.date(earlier.invoice_date, locale),
        amount: Format.currency(earlier.amount, locale)
      }
    end
  end

  # Money paid outside any invoice before this one was made, such as a card
  # deposit at checkout: refunds and Undos net off. Payments on an earlier
  # invoice are already counted by listing that invoice.
  defp paid_earlier(invoice, payments, locale) do
    paid =
      for payment <- payments,
          is_nil(payment.invoice_id),
          DateTime.before?(payment.paid_at, invoice.inserted_at),
          reduce: Decimal.new(0) do
        sum -> Decimal.add(sum, payment.amount)
      end

    if Decimal.positive?(paid), do: Format.currency(paid, locale)
  end
end
