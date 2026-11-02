defmodule Edenflowers.Payments.InvoicePdf do
  @moduledoc """
  Renders an Invoice's PDF with Typst (`priv/receipts/invoice.typ`), for an
  order or a Course booking alike.

  What an invoice prints is built once, when it is made (`content/1`), and
  frozen onto its `content`, so the PDF never changes after that: the admin
  download, the email and every resend render that same content. Only the
  printed labels are translated afresh at each render. The purchase's lines,
  totals and VAT per rate are the receipt's (`Orders.Receipt.build_payload/1`)
  as they stood then, so the two documents agree on the day it is made.
  Before them it lists what the purchase was already invoiced or paid, and
  after them what is due on this invoice, with the bank details, viitenumero
  and virtual barcode to pay it with.

  A Credit note renders from `priv/receipts/credit-note.typ`: the buyer and
  seller frozen on the credited Invoice, which Invoice it cancels and the
  amount it credits. It leaves out the purchase's lines.
  """

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Payments.Changes.SendInvoice
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoiceLabels
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.Payments.VirtualBarcode
  alias Edenflowers.Typst

  @receipt_keys [
    :lang,
    :fulfillment_method,
    :line_items,
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

  def generate(%Invoice{} = invoice), do: Typst.render("invoice-main.typ", "invoice", payload(invoice))

  def generate(%CreditNote{} = credit_note) do
    with {:ok, credit_note} <- Ash.load(credit_note, :invoice, authorize?: false) do
      Typst.render("credit-note-main.typ", "credit_note", build_payload(credit_note))
    end
  end

  @doc "What `generate/1` renders for an invoice: its frozen `content` with the labels in its language."
  def payload(%Invoice{content: content, locale: locale}),
    do: Map.put(content, "labels", InvoiceLabels.for_locale(locale))

  @doc """
  The content a new invoice freezes: `build_payload/1` for it and its
  purchase as they are now, with a booking's course in the invoice's
  language. Called once, by `Changes.FreezeInvoiceContent` as it is made.
  """
  def content(%Invoice{} = invoice) do
    with {:ok, invoice} <- load(invoice) do
      # Through JSON, so the invoice create returns reads the same as one loaded later from jsonb.
      {:ok, invoice |> SendInvoice.in_invoice_locale() |> build_payload() |> Jason.encode!() |> Jason.decode!()}
    end
  end

  defp load(invoice) do
    Ash.load(
      invoice,
      [
        order: Receipt.order_load() ++ [:cancelled?, invoices: :credit_note],
        course_registration: Receipt.registration_load() ++ [:cancelled?, invoices: :credit_note]
      ],
      authorize?: false
    )
  end

  # Exposed so payload serialization can be tested without invoking Typst.
  def build_payload(%CreditNote{invoice: %Invoice{content: content} = invoice} = credit_note) do
    locale = invoice.locale

    %{
      lang: Receipt.lang_from_locale(locale),
      labels: InvoiceLabels.for_locale(locale),
      number: credit_note.number,
      credit_date: Format.date(credit_note.credit_date, locale),
      invoice_number: invoice.number,
      invoice_date: Format.date(invoice.invoice_date, locale),
      customer_reference: invoice.customer_reference,
      reason: credit_note.reason,
      seller: Map.take(content["seller"], ["name", "business_id", "address"]),
      buyer: content["buyer"],
      amount: Format.currency(Decimal.negate(invoice.amount), locale)
    }
  end

  def build_payload(%Invoice{} = invoice) do
    locale = invoice.locale
    purchase = invoice.order || invoice.course_registration
    seller = Invoice.seller()
    earlier = earlier_invoices(invoice, purchase.invoices)
    paid = paid_earlier(invoice, purchase.payments)

    # In the invoice's language, which Jennie may have changed from the purchase's.
    %{purchase | locale: locale}
    |> Receipt.build_payload()
    |> Map.take(@receipt_keys)
    |> Map.merge(%{
      number: invoice.number,
      invoice_date: Format.date(invoice.invoice_date, locale),
      due_date: Format.date(invoice.due_date, locale),
      delivery_date: Format.date(delivery_date(purchase), locale),
      late_interest_rate:
        Localize.Number.to_string!(Invoice.late_interest_rate(), locale: locale, format: :percent, fractional_digits: 2),
      customer_reference: invoice.customer_reference,
      seller: seller,
      buyer: buyer(invoice),
      earlier_invoices:
        Enum.map(earlier, fn earlier_invoice ->
          %{
            number: earlier_invoice.number,
            invoice_date: Format.date(earlier_invoice.invoice_date, locale),
            amount: Format.currency(Decimal.negate(earlier_invoice.amount), locale)
          }
        end),
      paid_earlier: if(Decimal.positive?(paid), do: Format.currency(Decimal.negate(paid), locale)),
      remainder: remainder(invoice, purchase, earlier, paid, locale),
      amount: Format.currency(invoice.amount, locale),
      reference_number: ReferenceNumber.format(invoice.reference_number),
      virtual_barcode: VirtualBarcode.version_4(seller.iban, invoice.amount, invoice.reference_number, invoice.due_date)
    })
  end

  defp delivery_date(%Order{fulfillment_date: date}), do: date
  defp delivery_date(%CourseRegistration{course: course}), do: course.date

  defp buyer(%Invoice{business_customer: true} = invoice) do
    %{
      company_name: invoice.company_name,
      business_id: invoice.business_id,
      name: invoice.buyer_name,
      address: invoice.billing_address
    }
  end

  defp buyer(invoice) do
    %{company_name: nil, business_id: nil, name: invoice.buyer_name, address: invoice.buyer_address}
  end

  # Invoices are numbered in the order they were made, and never change, so
  # the earlier ones read the same however late this one is rendered. One
  # cancelled before this one was made asked for nothing, so it is left out;
  # one cancelled later still shows, as it stood when this one was sent.
  defp earlier_invoices(invoice, invoices) do
    for earlier <- Enum.sort_by(invoices, & &1.number),
        earlier.number < invoice.number,
        !cancelled_before?(earlier, invoice),
        do: earlier
  end

  defp cancelled_before?(%Invoice{credit_note: %CreditNote{number: number}}, invoice), do: number < invoice.number
  defp cancelled_before?(_earlier, _invoice), do: false

  # Money paid outside any invoice before this one was made, such as a card
  # deposit at checkout: refunds and Undos net off. Payments on an earlier
  # invoice are already counted by listing that invoice.
  defp paid_earlier(invoice, payments) do
    paid =
      for payment <- payments,
          is_nil(payment.invoice_id),
          DateTime.before?(payment.paid_at, invoice.inserted_at),
          reduce: Decimal.new(0) do
        sum -> Decimal.add(sum, payment.amount)
      end

    Decimal.max(paid, 0)
  end

  # The totals are a sum: the purchase's total, less what earlier invoices and
  # payments covered, is what this invoice asks for. When Jennie asks for less,
  # the rest gets a line of its own so the column still adds up: left to
  # invoice later, or, on a cancelled purchase, not charged at all.
  defp remainder(invoice, purchase, earlier, paid, locale) do
    covered = Enum.reduce(earlier, Decimal.add(paid, invoice.amount), &Decimal.add(&1.amount, &2))
    rest = Decimal.sub(printed_total(purchase), covered)

    if Decimal.positive?(rest) do
      %{
        label: if(purchase.cancelled?, do: "not-charged", else: "invoiced-later"),
        amount: Format.currency(Decimal.negate(rest), locale)
      }
    end
  end

  # The total the receipt part of the invoice prints, before any cancellation.
  defp printed_total(%Order{grand_total: total}), do: total
  defp printed_total(%CourseRegistration{amount: total}), do: total
end
