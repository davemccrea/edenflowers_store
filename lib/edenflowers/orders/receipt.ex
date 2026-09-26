defmodule Edenflowers.Orders.Receipt do
  @moduledoc """
  Renders the receipt PDF for an order or a course booking by shelling out to
  the Typst CLI.

  Deterministic over the placed order's snapshot columns, so the PDF
  bytes aren't persisted — `Order.receipt_sha256` records what was sent.
  Use `load_for_receipt/1` to load the aggregates `generate/1` expects.
  """

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Order.Calculations.Vat

  @typst_bin "typst"

  def load_for_receipt(order) do
    Ash.load(
      order,
      [
        :items_subtotal,
        :items_total,
        :discount,
        :promotion_applied?,
        :grand_total,
        line_items: [:subtotal, :total, :unit_price_ex_tax]
      ],
      authorize?: false
    )
  end

  def generate(%struct{} = record) when struct in [Order, CourseRegistration] do
    json = record |> build_payload() |> Jason.encode!()

    # Keep stderr separate — merging it would corrupt the PDF bytes on stdout.
    case System.cmd(@typst_bin, typst_args(json)) do
      {pdf, 0} -> {:ok, pdf}
      {output, status} -> {:error, {:typst_failed, status, output}}
    end
  end

  # Exposed so payload serialization can be tested without invoking Typst.
  def build_payload(%Order{} = order) do
    locale = order.locale

    %{
      lang: lang_from_locale(locale),
      order_reference: order.order_reference,
      ordered_at: Format.datetime(order.ordered_at, locale),
      customer_name: order.customer_name,
      customer_email: order.customer_email,
      fulfillment_method: to_string(order.fulfillment_method),
      fulfillment_date: Format.weekday_numeric_date(order.fulfillment_date, locale),
      recipient_name: order.recipient_name,
      recipient_phone_number: order.recipient_phone_number,
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
      grand_total: Format.currency(order.grand_total, locale)
    }
  end

  # Expects the registration's `course` loaded. A booking has one line and a
  # single VAT rate, so the breakdown is computed here rather than snapshotted.
  def build_payload(%CourseRegistration{} = registration) do
    locale = registration.locale
    course = registration.course
    base = net_of_vat(registration.amount, registration.tax_rate)
    amount = Format.currency(registration.amount, locale)

    %{
      lang: lang_from_locale(locale),
      order_reference: registration.reference,
      ordered_at: Format.datetime(registration.confirmed_at || registration.inserted_at, locale),
      customer_name: registration.name,
      customer_email: registration.email,
      fulfillment_method: "course",
      fulfillment_date:
        "#{Format.weekday_numeric_date(course.date, locale)}, " <>
          "#{Format.time(course.start_time, locale)}–#{Format.time(course.end_time, locale)}",
      venue_name: course.location_name,
      venue_address: course.location_address,
      recipient_name: nil,
      recipient_phone_number: nil,
      delivery_address: nil,
      delivery_instructions: nil,
      card_message: nil,
      line_items: [
        %{
          product_name: course.name,
          variant_size: nil,
          quantity: registration.seats,
          unit_price_ex_tax: Format.currency(net_of_vat(Decimal.div(registration.amount, registration.seats), registration.tax_rate), locale),
          tax_rate: Format.percentage(registration.tax_rate, locale),
          total: amount
        }
      ],
      items_subtotal: amount,
      fulfillment_fee: nil,
      discount: nil,
      vat_breakdown: [
        %{
          rate: Format.percentage(registration.tax_rate, locale),
          base: Format.currency(base, locale),
          tax: Format.currency(Decimal.sub(registration.amount, base), locale),
          gross: amount
        }
      ],
      grand_total: amount
    }
  end

  # Same split as `Vat.breakdown/1`: round the base, VAT is the remainder.
  defp net_of_vat(gross, rate), do: gross |> Decimal.div(Decimal.add(1, rate)) |> Decimal.round(2)

  # `total` is net of any promotion; the receipt states the discount once as
  # its own row, so the line column has to show the undiscounted subtotal or
  # the column won't sum to the row above it.
  defp line_item_payload(item, locale) do
    %{
      product_name: item.product_name,
      variant_size: variant_size_label(item.variant_size),
      quantity: item.quantity,
      unit_price_ex_tax: Format.currency(item.unit_price_ex_tax, locale),
      tax_rate: Format.percentage(item.tax_rate, locale),
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

  # Finnish law wants the VAT stated per rate — kuittipakkolaki 658/2013 § 4,
  # and AVL § 209 f for the simplified invoice every order under €400 falls
  # under. Prices are tax-inclusive, so each rate's gross is split into the
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

  defp variant_size_label(nil), do: nil
  defp variant_size_label(size), do: size |> to_string() |> String.capitalize()

  # `translations.toml` keys are two-letter subtags, but `order.locale` is e.g.
  # "sv-FI". `parse!/1` (not `validate_locale/1`, which is gated by
  # `:supported_locales`) just extracts the language subtag.
  defp lang_from_locale(locale) when is_binary(locale) do
    Localize.LanguageTag.parse!(locale).language |> to_string()
  end

  defp typst_args(json) do
    priv = :code.priv_dir(:edenflowers)

    [
      "compile",
      Path.join(priv, "receipts/main.typ"),
      "-",
      "--format",
      "pdf",
      "--font-path",
      Path.join(priv, "receipts/fonts"),
      "--input",
      "order=" <> json
    ]
  end
end
