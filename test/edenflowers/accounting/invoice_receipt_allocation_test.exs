defmodule Edenflowers.Accounting.InvoiceReceiptAllocationTest do
  use ExUnit.Case, async: true
  alias Edenflowers.Accounting.InvoiceReceiptAllocation

  @snapshot %{
    "vat_breakdown" => [
      %{"rate" => "25.5", "gross" => "0.05", "base" => "0.04", "vat" => "0.01"},
      %{"rate" => "14", "gross" => "0.05", "base" => "0.04", "vat" => "0.01"},
      %{"rate" => "0", "gross" => "0", "base" => "0", "vat" => "0"}
    ]
  }

  test "ten cent-sized receipts reconcile exactly, including frozen VAT and a free rate" do
    payments = for n <- 1..10, do: payment(n, "0.01")
    allocations = InvoiceReceiptAllocation.allocate(@snapshot, Enum.reverse(payments))
    totals = allocations |> Map.values() |> List.flatten() |> Enum.group_by(&Decimal.to_string(&1.rate))

    for rate <- ["0.14", "0.255"] do
      assert Decimal.equal?(sum(totals[rate], :gross), "0.05")
      assert Decimal.equal?(sum(totals[rate], :base), "0.04")
      assert Decimal.equal?(sum(totals[rate], :vat), "0.01")
    end

    assert Decimal.equal?(sum(totals["0"], :gross), "0")

    for {_id, rows} <- allocations do
      assert Decimal.equal?(sum(rows, :gross), "0.01")
      for row <- rows, do: assert(Decimal.equal?(Decimal.add(row.base, row.vat), row.gross))
    end
  end

  test "settlement, reversal and re-entry reconcile instead of accumulating rounded VAT" do
    receipts = [payment(1, "0.03"), payment(2, "0.07"), payment(3, "-0.03"), payment(4, "0.03")]
    rows = InvoiceReceiptAllocation.allocate(@snapshot, receipts) |> Map.values() |> List.flatten()
    assert Decimal.equal?(sum(rows, :gross), "0.10")
    assert Decimal.equal?(sum(rows, :base), "0.08")
    assert Decimal.equal?(sum(rows, :vat), "0.02")

    zero =
      InvoiceReceiptAllocation.allocate(@snapshot, receipts ++ [payment(5, "-0.10")]) |> Map.values() |> List.flatten()

    for field <- [:gross, :base, :vat], do: assert(Decimal.equal?(sum(zero, field), 0))
  end

  test "payment ids resolve equal timestamps deterministically and zero totals never divide" do
    receipts = [payment(1, "0.03"), %{payment(2, "0.07") | paid_at: payment(1, "0").paid_at}]

    assert InvoiceReceiptAllocation.allocate(@snapshot, receipts) ==
             InvoiceReceiptAllocation.allocate(@snapshot, Enum.reverse(receipts))

    zero = %{"vat_breakdown" => [%{"rate" => "0", "gross" => "0", "base" => "0", "vat" => "0"}]}
    assert [%{gross: gross}] = InvoiceReceiptAllocation.allocate(zero, [payment(1, "0")])["1"]
    assert Decimal.equal?(gross, 0)
  end

  defp payment(n, amount),
    do: %{id: to_string(n), amount: Decimal.new(amount), paid_at: DateTime.add(~U[2026-09-01 00:00:00Z], n)}

  defp sum(rows, field), do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(Map.fetch!(&1, field), &2))
end
