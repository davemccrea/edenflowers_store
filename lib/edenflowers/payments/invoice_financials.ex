defmodule Edenflowers.Payments.InvoiceFinancials do
  @moduledoc "Exact invoice arithmetic. Round each extended gross and VAT-exclusive base to cents, half up; VAT is their difference."

  @doc "Validate and calculate immutable numeric data, independently of presentation or locale."
  def build(lines) when is_list(lines) and lines != [] do
    lines = Enum.map(lines, &line/1)

    breakdown =
      lines
      |> Enum.group_by(& &1["vat_rate"])
      |> Enum.map(fn {rate, rows} -> Map.put(totals(rows), "rate", rate) end)
      |> Enum.sort_by(&Decimal.new(&1["rate"]), {:asc, Decimal})

    snapshot = totals(lines) |> Map.merge(%{"lines" => lines, "vat_breakdown" => breakdown})

    if Decimal.positive?(Decimal.new(snapshot["gross"])),
      do: {:ok, snapshot},
      else: {:error, "Invoice total must be positive"}
  rescue
    _ in [ArgumentError, Decimal.Error, KeyError] ->
      {:error, "Lines require a description, positive quantity, non-negative unit price and VAT rate between 0 and 100"}
  end

  def build(_), do: {:error, "At least one billed line is required"}

  defp line(input) do
    input = Map.new(input, fn {key, value} -> {to_string(key), value} end)
    description = description!(input["description"])
    quantity = decimal(input["quantity"])
    price = decimal(input["unit_price"])
    rate = decimal(input["vat_rate"])

    unless valid_amounts?(quantity, price, rate), do: raise(ArgumentError)

    gross = quantity |> Decimal.mult(price) |> cents()
    base = gross |> Decimal.div(Decimal.add(1, Decimal.div(rate, 100))) |> cents()

    %{
      "description" => description,
      "quantity" => value(quantity),
      "unit_price" => value(price),
      "vat_rate" => value(rate),
      "gross" => value(gross),
      "base" => value(base),
      "vat" => value(Decimal.sub(gross, base))
    }
  end

  defp description!(description) when is_binary(description) do
    case String.trim(description) do
      "" -> raise ArgumentError
      description -> description
    end
  end

  defp description!(_), do: raise(ArgumentError)

  defp valid_amounts?(quantity, price, rate) do
    Decimal.positive?(quantity) and Decimal.compare(price, 0) != :lt and
      Decimal.compare(rate, 0) != :lt and Decimal.compare(rate, 100) != :gt
  end

  defp totals(rows) do
    Map.new(["gross", "base", "vat"], fn key ->
      {key, rows |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, Decimal.new(&1[key]))) |> value()}
    end)
  end

  defp decimal(%Decimal{} = value), do: finite!(value)
  defp decimal(value) when is_binary(value) or is_integer(value), do: value |> Decimal.new() |> finite!()
  defp decimal(_), do: raise(ArgumentError)
  defp finite!(%Decimal{coef: coef} = value) when is_integer(coef), do: value
  defp finite!(_), do: raise(ArgumentError)
  defp cents(value), do: Decimal.round(value, 2, :half_up)
  defp value(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
end
