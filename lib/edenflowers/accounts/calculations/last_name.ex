defmodule Edenflowers.Accounts.Calculations.LastName do
  @moduledoc """
  Best-guess family name from a freeform full-name string, the counterpart to
  `FirstName`: everything after the first name, so the two join back into the
  full name.

    * `"Jane Doe"`         -> `"Doe"`
    * `"Jan van der Berg"` -> `"van der Berg"`
    * `"Smith, Jane"`      -> `"Smith"`
    * `"Madonna"` / `nil`  -> `nil`
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} when is_atom(source) -> {:ok, opts}
      _ -> {:error, "LastName calculation requires a `:source` atom option"}
    end
  end

  @impl true
  def load(_query, opts, _context), do: [opts[:source]]

  @impl true
  def calculate(records, opts, _context) do
    source = opts[:source]
    Enum.map(records, fn record -> extract(Map.get(record, source)) end)
  end

  def extract(nil), do: nil

  def extract(value) when is_binary(value) do
    case String.split(value, ",", parts: 2) do
      [last, _given] -> blank_to_nil(String.trim(last))
      [name] -> name |> String.split(~r/\s+/, trim: true) |> Enum.drop(1) |> Enum.join(" ") |> blank_to_nil()
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(name), do: name
end
