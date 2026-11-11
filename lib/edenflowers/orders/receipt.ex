defmodule Edenflowers.Orders.Receipt do
  @moduledoc """
  Generates order and course receipt PDFs on demand with the Typst CLI.

  Receipts use the loaded record, payments and current labels and seller details.
  Course receipts also use the current course details.
  Use `load_for_receipt/1` before `generate/1`.
  """

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.ReceiptLabels
  alias Edenflowers.Pricing
  alias Edenflowers.Typst

  @order_load [
    :items_subtotal,
    :items_total,
    :discount,
    :promotion_applied?,
    :grand_total,
    :contact_phone_number,
    :upcoming?,
    :gift_voucher_sale?,
    payments: [],
    line_items: [:subtotal, :total, :unit_price_ex_tax],
    gift_voucher_line: :gift_voucher
  ]

  @registration_load [:course, :upcoming?, payments: []]

  def order_load, do: @order_load
  def registration_load, do: @registration_load

  def load_for_receipt(%Order{} = order), do: Ash.load(order, @order_load, authorize?: false)

  def load_for_receipt(%CourseRegistration{} = registration),
    do: Ash.load(registration, @registration_load, authorize?: false)

  def attachment(pdf, reference) do
    Swoosh.Attachment.new({:data, pdf}, filename: "eden-flowers-#{reference}.pdf", content_type: "application/pdf")
  end

  def generate(%struct{} = record) when struct in [Order, CourseRegistration] do
    Typst.render("main.typ", "order", build_payload(record))
  end

  # Exposed so payload serialization can be tested without invoking Typst.
  def build_payload(%Order{} = order) do
    locale = order.locale

    %{
      lang: lang_from_locale(locale),
      labels: ReceiptLabels.for_receipt(locale, order.upcoming?),
      seller: seller(),
      order_reference: order.order_reference,
      ordered_at: Format.datetime(order.ordered_at, locale),
      customer_name: order.customer_name,
      customer_email: order.customer_email,
      fulfillment_method:
        if(order.gift_voucher_sale? == true, do: "gift-voucher", else: to_string(order.fulfillment_method)),
      fulfillment_date: fulfillment_date(order, locale),
      recipient_name: order.recipient_name,
      collect_voucher_card: order.collect_voucher_card,
      contact_phone_number: order.contact_phone_number,
      # Customer's typed address, not `geocoded_address` — HERE strips flat numbers and stair codes.
      delivery_address: order.delivery_address,
      delivery_instructions: order.delivery_instructions,
      card_message: order.card_message,
      venue_name: nil,
      venue_address: nil,
      line_items: Enum.map(order.line_items, &line_item_payload(&1, locale)),
      items_subtotal: Format.currency(order.items_subtotal, locale),
      fulfillment_fee: fulfillment_fee_payload(order, locale),
      discount: discount_payload(order, locale),
      vat_breakdown: vat_breakdown(order, locale),
      vat_note: vat_note(order),
      grand_total: Format.currency(order.grand_total, locale),
      payments: payments_payload(order.payments, locale)
    }
  end

  # Expects `registration_load/0` loaded. A booking has
  # one line and a single VAT rate, so the breakdown is computed here rather
  # than snapshotted.
  def build_payload(%CourseRegistration{} = registration) do
    locale = registration.locale
    course = registration.course
    base = Pricing.Vat.net_of_vat(registration.amount, registration.tax_rate)
    amount = Format.currency(registration.amount, locale)

    %{
      lang: lang_from_locale(locale),
      labels: ReceiptLabels.for_receipt(locale, registration.upcoming?),
      seller: seller(),
      order_reference: registration.reference,
      ordered_at: Format.datetime(registration.confirmed_at || registration.inserted_at, locale),
      customer_name: registration.name,
      customer_email: registration.email,
      fulfillment_method: "course",
      fulfillment_date:
        "#{Format.weekday_date(course.date, locale)}, " <>
          "#{Format.time(course.start_time, locale)}–#{Format.time(course.end_time, locale)}",
      venue_name: course.location_name,
      venue_address: course.location_address,
      recipient_name: nil,
      collect_voucher_card: false,
      contact_phone_number: nil,
      delivery_address: nil,
      delivery_instructions: nil,
      card_message: nil,
      line_items: [
        %{
          product_name: course.name,
          variant_size: nil,
          bow_colour: nil,
          quantity: registration.seats,
          unit_price_ex_tax:
            Format.currency(
              Pricing.Vat.net_of_vat(Decimal.div(registration.amount, registration.seats), registration.tax_rate),
              locale
            ),
          tax_rate: Format.percentage(registration.tax_rate, locale),
          total: amount
        }
      ],
      items_subtotal: amount,
      fulfillment_fee: nil,
      discount: nil,
      vat_note: nil,
      vat_breakdown: [
        %{
          rate: Format.percentage(registration.tax_rate, locale),
          base: Format.currency(base, locale),
          tax: Format.currency(Decimal.sub(registration.amount, base), locale),
          gross: amount
        }
      ],
      grand_total: amount,
      payments: payments_payload(registration.payments, locale)
    }
  end

  # A Gift voucher sale is dated by the voucher's expiry: it has no delivery.
  defp fulfillment_date(%{gift_voucher_sale?: true} = order, locale) do
    Format.date(order.gift_voucher_line.gift_voucher.expires_on, locale)
  end

  defp fulfillment_date(order, locale), do: Format.weekday_date(order.fulfillment_date, locale)

  defp vat_note(%{gift_voucher_sale?: true}), do: "gift-voucher"
  defp vat_note(_order), do: nil

  # Refunds aren't something the customer paid with, and payments recorded
  # before `payment_method_type` existed are left off so their receipts stay
  # as they were sent.
  defp payments_payload(payments, locale) do
    for payment <- Enum.sort_by(payments, & &1.paid_at, DateTime),
        payment.payment_method_type,
        Decimal.compare(payment.amount, 0) == :gt do
      payment_payload(payment, locale)
    end
  end

  # Show each payment's own date: a payment link or cash at pickup may be paid after the order date.
  defp payment_payload(payment, locale) do
    %{
      method: payment.payment_method_type,
      card_brand: payment.card_brand,
      card_last4: payment.card_last4,
      paid_on: Format.date(payment.paid_at, locale),
      amount: Format.currency(payment.amount, locale)
    }
  end

  # `total` is net of any promotion; the receipt states the discount once as
  # its own row, so the line column has to show the undiscounted subtotal or
  # the column won't sum to the row above it.
  defp line_item_payload(item, locale) do
    %{
      product_name: item.product_name,
      variant_size: item.variant_size && size_label(item.variant_size, locale),
      bow_colour: item.bow_colour && bow_colour_label(item.bow_colour, locale),
      quantity: item.quantity,
      unit_price_ex_tax: Format.currency(item.unit_price_ex_tax, locale),
      # Outside VAT, not taxed at 0 %.
      tax_rate: if(item.is_gift_voucher, do: "–", else: Format.percentage(item.tax_rate, locale)),
      total: Format.currency(item.subtotal, locale)
    }
  end

  # A zero fee is noise on a pickup receipt — drop the row rather than print
  # "Pickup fee 0,00 €".
  defp fulfillment_fee_payload(order, locale) do
    if positive?(order.fulfillment_fee) do
      Format.currency(order.fulfillment_fee, locale)
    end
  end

  # The VAT is stated per rate, as AVL § 209 f asks of a business buyer's
  # invoice and kuittipakkolaki 658/2013 § 4 of a receipt for an in-person
  # payment. (That act leaves out online sales, and a consumer needs no
  # invoice, so for most orders this is a courtesy.) Prices are tax-inclusive,
  # so each rate's gross is split into the
  # taxable base and the VAT contained in it. Rounding the base first and
  # taking the VAT as the remainder keeps the printed row adding up.
  defp vat_breakdown(order, locale) do
    order
    |> Vat.breakdown()
    |> Enum.map(fn %{rate: rate, base: base, vat: vat, gross: gross} ->
      %{
        rate: Format.percentage(rate, locale),
        base: Format.currency(base, locale),
        tax: Format.currency(vat, locale),
        gross: Format.currency(gross, locale)
      }
    end)
  end

  defp positive?(nil), do: false
  defp positive?(amount), do: Decimal.compare(amount, 0) == :gt

  # `order.discount` sums to 0 (not nil) when no promotion applies, so gate on `promotion_applied?`.
  defp discount_payload(order, locale) do
    if order.promotion_applied? do
      Format.currency(order.discount, locale)
    end
  end

  # The label is translated in the order's locale, not whatever locale the
  # process rendering the PDF happens to be in.
  defp size_label(size, locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      EdenflowersWeb.CoreComponents.variant_size_label(size)
    end)
  end

  defp bow_colour_label(colour, locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      String.downcase(Edenflowers.Catalog.BowColour.label(colour))
    end)
  end

  # Identify the seller in the receipt footer with its registered name, business ID and address.
  defp seller, do: Map.take(Application.fetch_env!(:edenflowers, :seller), [:name, :business_id, :address])

  @doc ~s(The language subtag Typst expects, as "sv" for "sv-FI": app locales include a region.)
  def lang_from_locale(locale) when is_binary(locale) do
    Localize.LanguageTag.parse!(locale).language |> to_string()
  end
end
