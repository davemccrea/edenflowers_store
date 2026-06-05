defmodule Edenflowers.Receipt do
  @moduledoc """
  Renders the order-receipt PDF by shelling out to the Typst CLI.

  Deterministic over the placed order's snapshot columns, so the PDF
  bytes aren't persisted — `Order.receipt_sha256` records what was sent.
  Use `load_for_receipt/1` to load the aggregates `generate/1` expects.
  """

  alias Edenflowers.Localize.Format
  alias Edenflowers.Store.Order

  @typst_bin "typst"

  def load_for_receipt(order) do
    Ash.load(
      order,
      [
        :items_subtotal,
        :discount,
        :promotion_applied?,
        :grand_total,
        :tax,
        line_items: [:total, :unit_price_ex_tax]
      ],
      authorize?: false
    )
  end

  def generate(%Order{} = order) do
    json = order |> build_payload() |> Jason.encode!()

    # Keep stderr separate — merging it would corrupt the PDF bytes on stdout.
    case System.cmd(@typst_bin, typst_args(json)) do
      {pdf, 0} -> {:ok, pdf}
      {output, status} -> {:error, {:typst_failed, status, output}}
    end
  end

  # Exposed so tests can golden-diff against sample JSON without invoking Typst.
  def build_payload(%Order{} = order) do
    locale = order.locale

    %{
      lang: lang_from_locale(locale),
      order_reference: order.order_reference,
      ordered_at: Format.datetime(order.ordered_at, locale),
      customer_name: order.customer_name,
      customer_email: order.customer_email,
      fulfillment_method: to_string(order.fulfillment_method),
      fulfillment_date: Format.date(order.fulfillment_date, locale),
      recipient_name: order.recipient_name,
      recipient_phone_number: order.recipient_phone_number,
      # Customer's typed address, not `geocoded_address` — HERE strips flat numbers and stair codes.
      delivery_address: order.delivery_address,
      delivery_instructions: order.delivery_instructions,
      card_message: order.card_message,
      line_items: Enum.map(order.line_items, &line_item_payload(&1, locale)),
      items_subtotal: Format.currency(order.items_subtotal, locale),
      fulfillment_fee: Format.currency(order.fulfillment_fee || 0, locale),
      discount: discount_payload(order, locale),
      tax: Format.currency(order.tax, locale),
      grand_total: Format.currency(order.grand_total, locale)
    }
  end

  defp line_item_payload(item, locale) do
    %{
      product_name: item.product_name,
      variant_size: variant_size_label(item.variant_size),
      quantity: item.quantity,
      unit_price: Format.currency(item.unit_price, locale),
      unit_price_ex_tax: Format.currency(item.unit_price_ex_tax, locale),
      tax_rate: Format.percentage(item.tax_rate, locale),
      total: Format.currency(item.total, locale)
    }
  end

  # `order.discount` sums to 0 (not nil) when no promotion applies, so gate on `promotion_applied?`.
  defp discount_payload(order, locale) do
    if order.promotion_applied? do
      Format.currency(order.discount, locale)
    end
  end

  defp variant_size_label(nil), do: nil
  defp variant_size_label(size), do: size |> to_string() |> String.capitalize()

  # `translations.toml` keys are two-letter, but `order.locale` is e.g. "sv-FI".
  defp lang_from_locale(locale) when is_binary(locale), do: String.slice(locale, 0, 2)

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
