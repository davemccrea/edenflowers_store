defmodule Edenflowers.Payments.InvoiceFinancialsTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Payments.InvoiceFinancials
  alias Edenflowers.Payments.InvoiceLine

  defp line(description, quantity, unit_price, vat_rate) do
    %InvoiceLine{
      description: description,
      quantity: quantity && Decimal.new(quantity),
      unit_price: unit_price && Decimal.new(unit_price),
      vat_rate: vat_rate && Decimal.new(vat_rate)
    }
  end

  test "line rounding is half up and each rate conserves gross = base + VAT" do
    lines = [
      line("Fractional", "1.5", "10.01", "25.5"),
      line("Same rate", "3", "0.01", "25.50"),
      line("Exempt", "1", "2", "0")
    ]

    assert {:ok, snapshot} = InvoiceFinancials.build(lines)
    assert hd(snapshot["lines"])["gross"] == "15.02"
    assert snapshot["gross"] == "17.05"
    assert length(snapshot["vat_breakdown"]) == 2

    for row <- snapshot["vat_breakdown"] ++ [snapshot] do
      assert Decimal.equal?(Decimal.add(row["base"], row["vat"]), row["gross"])
    end
  end

  test "VAT is taken out once per rate, as orders do, not line by line" do
    lines = for name <- ~w(A B C), do: line(name, "1", "1.00", "25.5")

    assert {:ok, %{"vat_breakdown" => [row]}} = InvoiceFinancials.build(lines)
    assert row["base"] == Decimal.to_string(Edenflowers.Pricing.Vat.net_of_vat(Decimal.new(3), Decimal.new("0.255")))
    assert row["base"] == "2.39"
    assert row["vat"] == "0.61"
  end

  test "nothing billed, an unfinished line or a zero total has no snapshot" do
    assert {:error, _} = InvoiceFinancials.build([])
    assert {:error, _} = InvoiceFinancials.build([line("Flowers", "1", nil, "25.5")])
    assert {:error, _} = InvoiceFinancials.build([line("  ", "1", "20", "25.5")])
    assert {:error, _} = InvoiceFinancials.build([line("Free sample", "1", "0", "25.5")])
  end
end
