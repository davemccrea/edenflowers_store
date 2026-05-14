defmodule Edenflowers.Receipt do
  @moduledoc """
  Renders the order-receipt PDF by shelling out to the Typst CLI.

  The Typst project lives under `priv/receipts/` and asserts a specific
  payload shape in `receipt.typ`. This module builds that payload from a
  loaded `Store.Order`, encodes it as JSON, and pipes it into
  `typst compile` via the `--input` flag (which accepts only strings).

  The renderer is deterministic: the same placed order always produces
  the same PDF, so we don't persist the bytes — `Order.receipt_sha256`
  is recorded after delivery as evidence of what was sent.

  ## Required order load

  `generate/1` expects an order with the following aggregates,
  calculations, and relationships already loaded:

      [:discount, :items_subtotal, :tax, :grand_total, :promotion_applied?,
       line_items: [:total]]

  Use `Edenflowers.Receipt.load_for_receipt/1` to load them in one step.
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
        line_items: [:total]
      ],
      authorize?: false
    )
  end

  @doc """
  Renders the PDF for a loaded order. Returns `{:ok, pdf_binary}` on
  success or `{:error, reason}` on a non-zero Typst exit.
  """
  def generate(%Order{} = order) do
    json = order |> build_payload() |> Jason.encode!()

    case System.cmd(@typst_bin, typst_args(json), stderr_to_stdout: true) do
      {pdf, 0} -> {:ok, pdf}
      {output, status} -> {:error, {:typst_failed, status, output}}
    end
  end

  @doc """
  Builds the payload map matching the Typst template's schema contract
  in `priv/receipts/receipt.typ`. Exposed separately from `generate/1`
  so tests can golden-diff it against the sample JSON fixtures without
  invoking the Typst binary.
  """
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
      # Customer-typed address, not the HERE-normalised one. The geocoded
      # version powers driver routing internally; the receipt is the
      # customer's record, so it should reflect their own words —
      # including flat numbers, stair codes, etc. that HERE strips.
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
      unit_price_ex_tax: Format.currency(unit_price_ex_tax(item), locale),
      tax_rate: Format.percentage(item.tax_rate, locale),
      total: Format.currency(item.total, locale)
    }
  end

  # The line-item `unit_price` is tax-inclusive (consumer-facing); the
  # template renders an "excl. VAT" column for the Finnish VAT receipt
  # convention. Derive instead of adding a new attribute — the inputs
  # (`unit_price`, `tax_rate`) are both snapshot fields, so this stays
  # deterministic with the rest of the order.
  defp unit_price_ex_tax(item) do
    Decimal.div(item.unit_price, Decimal.add(1, item.tax_rate))
  end

  # `order.discount` is `sum(line_items.discount)` — when no promotion
  # is applied, each line item's discount is 0 so the sum is 0, not nil.
  # The template treats `discount` as optional (may be `none`); render
  # the row only when a promotion was actually applied.
  defp discount_payload(order, locale) do
    if order.promotion_applied? do
      Format.currency(order.discount, locale)
    end
  end

  defp variant_size_label(nil), do: nil
  defp variant_size_label(size), do: size |> to_string() |> String.capitalize()

  # "sv-FI" → "sv". The Typst template reads order.lang to pick the
  # translation column in priv/receipts/translations.toml, which is keyed
  # by the two-letter language code.
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
