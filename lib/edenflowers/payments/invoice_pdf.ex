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

  A Credit note renders from `priv/receipts/credit-note.typ`: the credited
  Invoice's buyer and language, which Invoice it cancels and the amount it
  credits, with nothing to pay. It leaves out the purchase's lines, which may
  have changed since the Invoice was made.
  """

  alias Edenflowers.Format
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Payments.CreditNote
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

  @doc """
  The PDF's file name in the document's language: `lasku-1001.pdf`,
  `faktura-1001.pdf` or `invoice-1001.pdf` for an Invoice, and
  `hyvityslasku-1002.pdf`, `kreditnota-1002.pdf` or `credit-note-1002.pdf` for
  a Credit note, which needs its `invoice` loaded.
  """
  def filename(%Invoice{number: number, locale: locale}), do: "#{document_name(:invoice, locale)}-#{number}.pdf"

  def filename(%CreditNote{number: number, invoice: %Invoice{locale: locale}}),
    do: "#{document_name(:credit_note, locale)}-#{number}.pdf"

  defp document_name(:invoice, "fi"), do: "lasku"
  defp document_name(:invoice, "sv-FI"), do: "faktura"
  defp document_name(:invoice, _english), do: "invoice"
  defp document_name(:credit_note, "fi"), do: "hyvityslasku"
  defp document_name(:credit_note, "sv-FI"), do: "kreditnota"
  defp document_name(:credit_note, _english), do: "credit-note"

  @doc "The PDF as an email attachment, named by `filename/1`."
  def attachment(pdf, document) do
    Swoosh.Attachment.new({:data, pdf}, filename: filename(document), content_type: "application/pdf")
  end

  def generate(%Invoice{} = invoice) do
    with {:ok, invoice} <- load(invoice) do
      Typst.render("invoice-main.typ", "invoice", build_payload(invoice))
    end
  end

  def generate(%CreditNote{} = credit_note) do
    with {:ok, credit_note} <- Ash.load(credit_note, [invoice: [:order, :course_registration]], authorize?: false) do
      Typst.render("credit-note-main.typ", "credit_note", build_payload(credit_note))
    end
  end

  @doc "Loads the purchase, its receipt data, invoices and payments, which `build_payload/1` expects."
  def load(invoice) do
    Ash.load(
      invoice,
      [
        order: Receipt.order_load() ++ [invoices: :credit_note],
        course_registration: [:course, :payments, invoices: :credit_note]
      ],
      authorize?: false
    )
  end

  # Exposed so payload serialization can be tested without invoking Typst.
  def build_payload(%CreditNote{invoice: invoice} = credit_note) do
    locale = invoice.locale

    {reference, method} =
      case invoice do
        %{order: %{order_reference: reference, fulfillment_method: method}} -> {reference, to_string(method)}
        %{course_registration: %{reference: reference}} -> {reference, "course"}
      end

    %{
      lang: Receipt.lang_from_locale(locale),
      labels: InvoiceLabels.for_locale(locale),
      number: credit_note.number,
      credit_date: Format.date(credit_note.credit_date, locale),
      credits: InvoiceLabels.credits(invoice.number, Format.date(invoice.invoice_date, locale), locale),
      order_reference: reference,
      fulfillment_method: method,
      customer_reference: invoice.customer_reference,
      reason: credit_note.reason,
      seller: Map.take(seller(invoice), [:name, :business_id, :address]),
      buyer: buyer(invoice),
      amount: Format.currency(Decimal.negate(invoice.amount), locale)
    }
  end

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
  # the earlier ones read the same however late this one is rendered. One
  # cancelled before this one was made asked for nothing, so it is left out;
  # one cancelled later still shows, as it stood when this one was sent.
  defp earlier_invoices(invoice, invoices, locale) do
    for earlier <- Enum.sort_by(invoices, & &1.number),
        earlier.number < invoice.number,
        !cancelled_before?(earlier, invoice) do
      %{
        number: earlier.number,
        invoice_date: Format.date(earlier.invoice_date, locale),
        amount: Format.currency(earlier.amount, locale)
      }
    end
  end

  defp cancelled_before?(%Invoice{credit_note: %CreditNote{number: number}}, invoice), do: number < invoice.number
  defp cancelled_before?(_earlier, _invoice), do: false

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
