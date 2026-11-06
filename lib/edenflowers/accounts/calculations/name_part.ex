defmodule Edenflowers.Accounts.Calculations.NamePart do
  @moduledoc """
  A best guess at part of a name typed as one free-text field, read from the
  `source` attribute. `part: :first` is its first word and `:last` the rest, so
  "Mary Anne Smith" gives "Mary" and "Anne Smith". `:initials` takes the first
  letters of its first and last words, or of the `fallback` attribute, such as
  the email, when there's no name.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, opts, _context), do: [opts[:source] | List.wrap(opts[:fallback])]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record -> part(opts[:part], words(Map.get(record, opts[:source])), record, opts) end)
  end

  def first(name), do: name |> words() |> List.first()

  defp part(:first, words, _record, _opts), do: List.first(words)
  defp part(:last, [_first | [_ | _] = rest], _record, _opts), do: Enum.join(rest, " ")
  defp part(:last, _words, _record, _opts), do: nil
  defp part(:initials, [word], _record, _opts), do: initial(word)
  defp part(:initials, [first | rest], _record, _opts), do: initial(first) <> initial(List.last(rest))

  defp part(:initials, [], record, opts),
    do: opts[:fallback] && record |> Map.get(opts[:fallback]) |> to_string() |> initial()

  defp words(nil), do: []
  defp words(name), do: String.split(name, ~r/\s+/, trim: true)

  defp initial(word), do: word |> String.first() |> String.upcase()
end
