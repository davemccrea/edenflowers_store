defmodule Edenflowers.Catalog.ProductType do
  @moduledoc """
  What kind of thing a category sells, which decides the details each of its sizes has.
  A new kind of product needs a value here and its keys, labels and wording below.
  """

  use Ash.Type.Enum, values: [:flowers, :card, :plant, :chocolate, :other]
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "shared"]

  @doc "The `ProductVariant` attributes a size of the type has, in display order."
  def attribute_keys(:flowers), do: [:height_cm, :stem_count]
  def attribute_keys(:card), do: [:dimensions_cm]
  def attribute_keys(:plant), do: [:height_cm, :pot_cm]
  def attribute_keys(:chocolate), do: [:weight_g, :pieces]
  def attribute_keys(:other), do: []

  @doc "The admin form's label for an attribute."
  def label(:height_cm), do: ~t"Height (cm)"
  def label(:stem_count), do: ~t"Stems"
  def label(:dimensions_cm), do: ~t"Dimensions (cm)"
  def label(:pot_cm), do: ~t"Pot (cm)"
  def label(:weight_g), do: ~t"Weight (g)"
  def label(:pieces), do: ~t"Pieces"

  @doc """
  A size's details for customers, such as "30–40 cm · 10–12 stems", or nil when it has none.
  Attributes the type doesn't use are left out, so changing a category's type hides stale ones.
  """
  def describe(type, variant) do
    parts =
      for key <- attribute_keys(type),
          value = Map.get(variant, key),
          do: describe_value(key, value)

    if parts != [], do: Enum.join(parts, " · ")
  end

  defp describe_value(:height_cm, value), do: "#{value} cm"
  defp describe_value(:stem_count, value), do: ~t"#{count = value} stems"
  defp describe_value(:dimensions_cm, value), do: "#{value} cm"
  defp describe_value(:pot_cm, value), do: ~t"Pot #{size = value} cm"
  defp describe_value(:weight_g, value), do: "#{value} g"
  defp describe_value(:pieces, value), do: ~t"#{count = value} pieces"
end
