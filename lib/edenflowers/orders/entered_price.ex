defmodule Edenflowers.Orders.EnteredPrice do
  @moduledoc """
  What an order Jennie is entering or editing will cost once saved, priced
  from the same params `:place_custom` and `:edit` take, so she can tell a
  customer on the phone before she places it.

  Each line is priced as `LineItem`'s `:enter` prices it, the card as
  `EnterCardLine` adds it, the fee as `PriceFulfillment` and the order's
  `fee_for_cart` charge it, and VAT by `Vat.compute_breakdown/1`, as the order's
  snapshot is. A delivery address is priced by the quote the form already looked
  up, so nothing is geocoded here.

  A line that isn't filled in yet is left out. The fee is nil while it can't be
  priced, and the total then leaves it out.
  """

  alias Edenflowers.Catalog
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Pricing.TaxRate
  alias Edenflowers.Types.Price

  @type delivery_quote :: %{fee: Decimal.t(), in_free_delivery_zone: boolean()} | nil

  @doc """
  `order` is the order being edited, with its `line_items`, or nil for a new
  one. `delivery_quote` prices a delivery address the order doesn't already have.
  """
  @spec calculate(Orders.Order.t() | nil, map(), delivery_quote()) :: %{
          lines: [%{name: String.t(), quantity: pos_integer(), total: Decimal.t()}],
          fulfillment_fee: Decimal.t() | nil,
          free_delivery?: boolean(),
          vat: Decimal.t(),
          total: Decimal.t()
        }
  def calculate(order, params, delivery_quote) do
    lines =
      params
      |> Map.get("line_items", [])
      |> as_list()
      |> Enum.concat(card(params))
      |> Enum.map(&line(&1, order))
      |> Enum.reject(&is_nil/1)
      |> apply_promotion(order)

    free_delivery? = Enum.any?(lines, & &1.free_delivery)
    {fee, fee_tax_rate} = fulfillment_fee(order, params, delivery_quote, free_delivery?)

    vat_rows =
      Vat.compute_breakdown(%{
        line_items: lines,
        fulfillment_fee: fee,
        fulfillment_tax_rate: fee_tax_rate
      })

    items_total = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.total, &2))

    %{
      lines: Enum.map(lines, &Map.take(&1, [:name, :quantity, :total])),
      fulfillment_fee: fee,
      free_delivery?: free_delivery?,
      vat: Enum.reduce(vat_rows, Decimal.new(0), &Decimal.add(&1.vat, &2)),
      total: Decimal.add(items_total, fee || 0)
    }
  end

  # The form sends nested lines indexed by position; tests send a list.
  defp as_list(lines) when is_map(lines),
    do: lines |> Enum.sort_by(fn {index, _} -> String.to_integer(index) end) |> Enum.map(&elem(&1, 1))

  defp as_list(lines), do: lines

  defp card(params) do
    variant_id = blank_to_nil(params["card_variant_id"])
    if variant_id && params["gift"] in [true, "true"], do: [%{"card_variant_id" => variant_id}], else: []
  end

  defp line(%{"card_variant_id" => variant_id}, order) do
    case order && Enum.find(order.line_items, &(&1.is_card && &1.product_variant_id == variant_id)) do
      nil -> from_variant(variant_id, 1)
      line_item -> from_line_item(line_item, 1)
    end
  end

  defp line(params, order) do
    case quantity(params["quantity"]) do
      quantity when is_integer(quantity) and quantity > 0 ->
        cond do
          id = blank_to_nil(params["id"]) ->
            order && order.line_items |> Enum.find(&(&1.id == id)) |> from_line_item(quantity)

          params["kind"] == "custom" ->
            custom(params, quantity)

          variant_id = blank_to_nil(params["product_variant_id"]) ->
            from_variant(variant_id, quantity)

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  defp from_line_item(nil, _quantity), do: nil

  defp from_line_item(line_item, quantity) do
    priced(line_item.product_name, quantity, line_item.unit_price, line_item.tax_rate, line_item.free_delivery)
  end

  defp from_variant(variant_id, quantity) do
    case Catalog.get_variant_by_id(variant_id, load: [product: [:tax_rate]], authorize?: false) do
      {:ok, variant} ->
        product = variant.product
        priced(product.name, quantity, variant.price, product.tax_rate.percentage, product.free_delivery)

      _ ->
        nil
    end
  end

  defp custom(params, quantity) do
    with name when not is_nil(name) <- blank_to_nil(params["product_name"]),
         {:ok, price} when not is_nil(price) <- Ash.Type.cast_input(Price, params["unit_price"]),
         tax_rate_id when not is_nil(tax_rate_id) <- blank_to_nil(params["tax_rate_id"]),
         {:ok, tax_rate} <- Ash.get(TaxRate, tax_rate_id, authorize?: false) do
      priced(name, quantity, price, tax_rate.percentage, false)
    else
      _ -> nil
    end
  end

  defp priced(name, quantity, unit_price, tax_rate, free_delivery) do
    subtotal = Decimal.mult(unit_price, quantity)

    %{
      name: name,
      quantity: quantity,
      subtotal: subtotal,
      total: subtotal,
      tax_rate: tax_rate,
      free_delivery: free_delivery
    }
  end

  # As the order's `promotion_applied?` and each line's `discount`.
  defp apply_promotion(lines, %{promotion_id: promotion_id, discount_rate: rate} = order)
       when not is_nil(promotion_id) and not is_nil(rate) do
    subtotal = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.subtotal, &2))
    minimum = order.promotion_minimum_cart_total

    if is_nil(minimum) or Decimal.compare(subtotal, minimum) != :lt do
      Enum.map(lines, &%{&1 | total: Decimal.sub(&1.subtotal, Decimal.round(Decimal.mult(&1.subtotal, rate), 2))})
    else
      lines
    end
  end

  defp apply_promotion(lines, _order), do: lines

  defp fulfillment_fee(order, params, delivery_quote, free_delivery?) do
    option_id = blank_to_nil(params["fulfillment_option_id"]) || (order && order.fulfillment_option_id)
    override = price(params["fulfillment_fee_override"])

    with {:ok, option} <- option(option_id),
         {:ok, quoted, in_zone, tax_rate} <- quoted(order, params, option, override, delivery_quote) do
      # Jennie's own fee is charged as she set it, as `fee_for_cart` does.
      fee = override || Orders.charged_fulfillment_fee!(quoted, in_zone, free_delivery?)
      {fee, tax_rate}
    else
      _ -> {nil, nil}
    end
  end

  defp option(nil), do: :error
  defp option(id), do: Fulfillment.get_option_by_id(id, load: [:tax_rate], authorize?: false)

  # As `PriceFulfillment`: an edit leaving the option, address and own fee alone keeps the order's fee.
  defp quoted(order, params, option, override, delivery_quote) do
    cond do
      order && unpriced_fields_unchanged?(order, params, option, override) ->
        {:ok, order.quoted_fulfillment_fee, order.in_free_delivery_zone, order.fulfillment_tax_rate}

      override ->
        {:ok, override, false, option.tax_rate.percentage}

      option.fulfillment_method == :pickup ->
        %{fulfillment_fee: fee, in_free_delivery_zone: in_zone} = Fee.calculate(option, 0)
        {:ok, fee, in_zone, option.tax_rate.percentage}

      delivery_quote ->
        {:ok, delivery_quote.fee, delivery_quote.in_free_delivery_zone, option.tax_rate.percentage}

      true ->
        :error
    end
  end

  defp unpriced_fields_unchanged?(order, params, option, override) do
    address = params |> Map.get("delivery_address", order.delivery_address) |> blank_to_nil()

    option.id == order.fulfillment_option_id and
      (option.fulfillment_method == :pickup or trim(address) == trim(order.delivery_address)) and
      same_amount?(override, order.fulfillment_fee_override)
  end

  defp same_amount?(nil, nil), do: true
  defp same_amount?(nil, _), do: false
  defp same_amount?(_, nil), do: false
  defp same_amount?(a, b), do: Decimal.equal?(a, b)

  defp quantity(quantity) when is_integer(quantity), do: quantity

  defp quantity(quantity) when is_binary(quantity) do
    case Integer.parse(String.trim(quantity)) do
      {quantity, ""} -> quantity
      _ -> nil
    end
  end

  defp quantity(_quantity), do: nil

  defp price(value) do
    case Ash.Type.cast_input(Price, value) do
      {:ok, price} -> price
      _ -> nil
    end
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
