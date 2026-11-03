defmodule Edenflowers.Payments.InvoiceFinancials do
  @moduledoc "Exact invoice arithmetic. Round each extended gross and VAT-exclusive base to cents, half up; VAT is their difference."

  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @doc """
  The numeric snapshot frozen on issuance, from complete InvoiceLines: each
  line's and each VAT rate's gross, base and VAT, and the totals, as
  strings. An error message while a line is missing a field or nothing is
  billed.
  """
  def build([]), do: {:error, ~t"Add at least one item."}

  def build(lines) when is_list(lines) do
    if Enum.all?(lines, &complete?/1) do
      lines = Enum.map(lines, &line/1)

      breakdown =
        lines
        |> Enum.group_by(& &1["vat_rate"])
        |> Enum.map(fn {rate, rows} -> Map.put(totals(rows), "rate", rate) end)
        |> Enum.sort_by(&Decimal.new(&1["rate"]), {:asc, Decimal})

      snapshot = totals(lines) |> Map.merge(%{"lines" => lines, "vat_breakdown" => breakdown})

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
    gross = line.quantity |> Decimal.mult(line.unit_price) |> cents()
    base = gross |> Decimal.div(Decimal.add(1, Decimal.div(line.vat_rate, 100))) |> cents()

    %{
      "description" => String.trim(line.description),
      "quantity" => value(line.quantity),
      "unit_price" => value(line.unit_price),
      "vat_rate" => value(line.vat_rate),
      "gross" => value(gross),
      "base" => value(base),
      "vat" => value(Decimal.sub(gross, base))
    }
  end

  defp totals(rows) do
    Map.new(["gross", "base", "vat"], fn key ->
      {key, rows |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, Decimal.new(&1[key]))) |> value()}
    end)
  end

  defp cents(value), do: Decimal.round(value, 2, :half_up)
  defp value(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
end
