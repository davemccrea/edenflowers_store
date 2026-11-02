defmodule Edenflowers.Accounting.InvoiceReceiptAllocation do
  @moduledoc """
  Allocates cash receipts from an invoice's frozen numeric VAT breakdown.

  Sort receipts by paid_at then id. Allocate cumulative gross by each rate's
  frozen gross proportion, round half up, and give the residual cent to the
  largest gross (ties go to the lower rate). Allocate cumulative base within
  each rate by its frozen base/gross proportion; VAT is gross minus base.
  Each receipt is the difference between consecutive cumulative allocations.
  Thus full settlement exactly reproduces frozen gross/base/VAT, and reversing
  receipts back to zero also reverses every cent, without rounding drift.
  """

  alias Edenflowers.Accounting.MonthlyReport

  def allocate(snapshot, payments) do
    breakdown =
      snapshot["vat_breakdown"]
      |> Enum.map(fn row ->
        %{
          rate: Decimal.div(Decimal.new(row["rate"]), 100),
          gross: Decimal.new(row["gross"]),
          base: Decimal.new(row["base"])
        }
      end)
      |> Enum.sort_by(& &1.rate, Decimal)

    {allocations, _} =
      payments
      |> Enum.sort(fn a, b ->
        case DateTime.compare(a.paid_at, b.paid_at) do
          :eq -> a.id <= b.id
          :lt -> true
          :gt -> false
        end
      end)
      |> Enum.map_reduce(Decimal.new(0), fn payment, before ->
        after_amount = Decimal.add(before, payment.amount)
        previous = cumulative(before, breakdown)
        current = cumulative(after_amount, breakdown)

        rows =
          Enum.zip_with(current, previous, fn row, old ->
            %{
              rate: row.rate,
              gross: Decimal.sub(row.gross, old.gross),
              base: Decimal.sub(row.base, old.base),
              vat: Decimal.sub(row.vat, old.vat)
            }
          end)

        {{payment.id, rows}, after_amount}
      end)

    Map.new(allocations)
  end

  defp cumulative(amount, breakdown) do
    shares = Map.new(MonthlyReport.split_by_rate(amount, breakdown))

    Enum.map(breakdown, fn row ->
      gross = Map.get(shares, row.rate, Decimal.new(0))

      base =
        if Decimal.equal?(row.gross, 0),
          do: Decimal.new(0),
          else: gross |> Decimal.mult(row.base) |> Decimal.div(row.gross) |> Decimal.round(2, :half_up)

      %{rate: row.rate, gross: gross, base: base, vat: Decimal.sub(gross, base)}
    end)
  end
end
