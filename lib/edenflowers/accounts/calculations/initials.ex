defmodule Edenflowers.Accounts.Calculations.Initials do
  @moduledoc """
  Best-guess initials from a freeform personal name.

  The calculation mirrors the checkout/account reality: names are stored as a
  single field, so initials are a presentation hint rather than structured
  identity data.
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} when is_atom(source) -> {:ok, opts}
      _ -> {:error, "Initials calculation requires a `:source` atom option"}
    end
  end

  @impl true
  def load(_query, opts, _context), do: [opts[:source]]

  @impl true
  def calculate(records, opts, _context) do
    source = opts[:source]
    Enum.map(records, fn record -> extract(Map.get(record, source)) end)
  end

  defp extract(nil), do: nil

  defp extract(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      name -> name |> initials_parts() |> initials()
    end
  end

  defp initials_parts(name) do
    case String.split(name, ",", parts: 2) do
      [last, given] -> [given, last]
      [single] -> String.split(single, ~r/\s+/, trim: true)
    end
  end

  defp initials(parts) do
    parts
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      [single] -> initial(single)
      [first | rest] -> initial(first) <> initial(List.last(rest))
    end
    |> String.upcase()
  end

  defp initial(value), do: value |> String.first() |> Kernel.||("")
end
