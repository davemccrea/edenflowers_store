defmodule Edenflowers.Accounts.Calculations.FirstName do
  @moduledoc """
  Best-guess extraction of a first name from a freeform full-name string.

  Customers type their name as a single field at checkout, so we never have a
  reliable structural split. This calculation handles the common shapes:

    * `"Jane Doe"`              -> `"Jane"`
    * `"Smith, Jane"`           -> `"Jane"`  (comma-inverted form)
    * `"  jane  "`              -> `"jane"`  (whitespace tolerated; no case mangling)
    * `"Madonna"`               -> `"Madonna"` (mononym; the whole string is the first name)
    * `nil` / `""` / whitespace -> `nil`

  Multi-word given names ("Mary Anne") collapse to the first token. That's the
  accepted trade-off for a heuristic — if a use case ever needs structured
  given/family fields, capture them separately rather than extending this.

  Used as a module calculation on resources that store a freeform name string.
  Pass `source:` to point it at the right attribute:

      calculate :customer_first_name, :string,
        {Edenflowers.Accounts.Calculations.FirstName, source: :customer_name}
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :source) do
      {:ok, source} when is_atom(source) -> {:ok, opts}
      _ -> {:error, "FirstName calculation requires a `:source` atom option"}
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
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed |> handle_comma_inversion() |> first_token()
    end
  end

  defp handle_comma_inversion(name) do
    case String.split(name, ",", parts: 2) do
      [_last, given] -> String.trim(given)
      [single] -> single
    end
  end

  defp first_token(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> List.first()
  end
end
