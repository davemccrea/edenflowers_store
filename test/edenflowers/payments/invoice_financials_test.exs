defmodule Edenflowers.Payments.InvoiceFinancialsTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Payments.InvoiceFinancials

  test "line rounding is half up and each rate conserves gross = base + VAT" do
    lines = [
      %{"description" => "Fractional", "quantity" => "1.5", "unit_price" => "10.01", "vat_rate" => "25.5"},
      %{"description" => "Same rate", "quantity" => "3", "unit_price" => "0.01", "vat_rate" => "25.50"},
      %{"description" => "Exempt", "quantity" => "1", "unit_price" => "2", "vat_rate" => "0"}
    ]

    assert {:ok, snapshot} = InvoiceFinancials.build(lines)
    assert hd(snapshot["lines"])["gross"] == "15.02"
    assert snapshot["gross"] == "17.05"
    assert length(snapshot["vat_breakdown"]) == 2

    for row <- snapshot["lines"] ++ snapshot["vat_breakdown"] ++ [snapshot] do
      assert Decimal.equal?(Decimal.add(row["base"], row["vat"]), row["gross"])
    end
  end

  test "rejects non-finite, float, negative, zero-total and missing data" do
    line = %{"description" => "Flowers", "quantity" => "1", "unit_price" => "20", "vat_rate" => "25.5"}

    for {key, value} <- [
          {"quantity", "NaN"},
          {"quantity", "Infinity"},
          {"quantity", "-1"},
          {"unit_price", "-0.01"},
          {"unit_price", 1.1},
          {"unit_price", "0"},
          {"vat_rate", "100.1"},
          {"vat_rate", "-1"},
          {"description", "  "}
        ] do
      assert {:error, _} = InvoiceFinancials.build([Map.put(line, key, value)])
    end
  end
end
