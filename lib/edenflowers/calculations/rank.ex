defmodule Edenflowers.Calculations.Rank do
  @moduledoc """
  The position of the `field` attribute's value in `order`, counting from 1, or nil when it is nil or not listed.
  Enums are stored as text, so sorting on one runs A–Z by its English atom; a table sorts on this instead to follow the
  enum's own order, which is also the order its filter offers.
  """
  use Ash.Resource.Calculation

  @impl true
  def expression(opts, _context) do
    field = opts[:field]

    opts[:order]
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.reduce(nil, fn {value, rank}, rest ->
      expr(if ^ref(field) == ^value, do: ^rank, else: ^rest)
    end)
  end
end
