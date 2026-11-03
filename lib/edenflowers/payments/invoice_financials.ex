defmodule Edenflowers.Payments.InvoiceFinancials do
  @moduledoc """
  Exact invoice arithmetic, by the same rule as orders and receipts. Each
  line's gross is rounded to cents, half up. The VAT-exclusive base is taken
  once per VAT rate, from that rate's total gross (`Vat.net_of_vat/2`), and
  the VAT is their difference: the per-rate figures the VAT Act asks an
  invoice to state, without rounding drift from many lines.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Pricing.Vat

  @doc """
  The numeric snapshot frozen on issuance, from complete InvoiceLines: each
  line's gross, each VAT rate's gross, base and VAT, and the totals, as
  strings. An error message while a line is missing a field or nothing is
  billed.
  """
  def build([]), do: {:error, ~t"Add at least one item."}

  def build(lines) when is_list(lines) do
    if Enum.all?(lines, &complete?/1) do
      lines = Enum.map(lines, &line/1)

      breakdown =
        lines
        |> Enum.group_by(& &1["vat_rate"], &Decimal.new(&1["gross"]))
        |> Enum.map(fn {rate, grosses} -> rate_row(rate, Enum.reduce(grosses, &Decimal.add/2)) end)
        |> Enum.sort_by(&Decimal.new(&1["rate"]), {:asc, Decimal})

      snapshot = breakdown |> totals() |> Map.merge(%{"lines" => lines, "vat_breakdown" => breakdown})

      if Decimal.positive?(Decimal.new(snapshot["gross"])),
        do: {:ok, snapshot},
        else: {:error, ~t"The invoice total must be more than zero."}
    else
      {:error, ~t"Complete the items to see the total."}
    end
  end

  def build(_lines), do: {:error, ~t"Complete the items to see the total."}

  @doc "Whether a line has every field issuing needs."
  def complete?(line) do
    is_binary(line.description) and String.trim(line.description) != "" and
      Enum.all?([line.quantity, line.unit_price, line.vat_rate], &is_struct(&1, Decimal))
  end

  defp line(line) do
    %{
      "description" => String.trim(line.description),
      "quantity" => value(line.quantity),
      "unit_price" => value(line.unit_price),
      "vat_rate" => value(line.vat_rate),
      "gross" => line.quantity |> Decimal.mult(line.unit_price) |> Decimal.round(2, :half_up) |> value()
    }
  end

  defp rate_row(rate, gross) do
    base = Vat.net_of_vat(gross, Decimal.div(Decimal.new(rate), 100))
    %{"rate" => rate, "gross" => value(gross), "base" => value(base), "vat" => value(Decimal.sub(gross, base))}
  end

  defp totals(rows) do
    Map.new(["gross", "base", "vat"], fn key ->
      {key, rows |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, Decimal.new(&1[key]))) |> value()}
    end)
  end

  defp value(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
end
