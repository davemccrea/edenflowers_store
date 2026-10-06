defmodule Edenflowers.Orders.Calculations.Vat do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:fulfillment_fee, :fulfillment_tax_rate, line_items: [:tax_rate, :total]]
  end

  @impl true
  def calculate(orders, _opts, _context), do: Enum.map(orders, &total/1)

  def total(order) do
    order
    |> breakdown()
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.vat, &2))
  end

  def breakdown(%{state: :placed, vat_breakdown: rows}) when is_list(rows), do: rows

  def breakdown(%{state: :placed}) do
    raise "placed order is missing its VAT breakdown snapshot"
  end

  def breakdown(order), do: compute_breakdown(order)

  @doc """
  The breakdown worked out from the order's lines and fee, ignoring any
  snapshot. What a snapshot is taken from, including when an unpaid custom
  order is edited after it was placed.
  """
  def compute_breakdown(order) do
    order.line_items
    |> Enum.map(&{&1.tax_rate, &1.total})
    |> Enum.concat(fulfillment_fee_entry(order))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0), {:desc, Decimal})
    |> Enum.map(fn {rate, amounts} ->
      gross = Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
      base = net_of_vat(gross, rate)

      %{rate: rate, base: base, vat: Decimal.sub(gross, base), gross: gross}
    end)
  end

  @doc """
  The taxable base in a tax-inclusive amount, rounded to cents. VAT is taken as
  the remainder so base + VAT always equals the gross.
  """
  def net_of_vat(gross, rate), do: gross |> Decimal.div(Decimal.add(1, rate)) |> Decimal.round(2)

  defp fulfillment_fee_entry(%{fulfillment_fee: fee, fulfillment_tax_rate: rate})
       when not is_nil(fee) and not is_nil(rate) do
    if Decimal.positive?(fee), do: [{rate, fee}], else: []
  end

  defp fulfillment_fee_entry(_order), do: []
end
