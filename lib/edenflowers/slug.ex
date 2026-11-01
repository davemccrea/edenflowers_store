defmodule Edenflowers.Slug do
  @moduledoc """
  Turns a name into the readable part of a URL, like `/product/red-rose-bouquet`.
  """

  @doc """
  Lowercase ASCII letters, digits and single hyphens: accents are dropped
  (å, ä and ö become a, a and o), spaces become hyphens and anything else goes,
  so "Vårkrans Workshop!" becomes "varkrans-workshop".

      iex> Edenflowers.Slug.slugify("Vårkrans  Workshop!")
      "varkrans-workshop"
  """
  def slugify(nil), do: ""

  def slugify(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end

  @doc """
  `base`, or `base-2`, `base-3`, … whichever `taken?` first says is free.
  """
  def unique(base, taken?) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not taken?.(&1)))
  end
end
