defmodule Edenflowers.Catalog.ProductVariantSize do
  @moduledoc """
  The named product sizes and the card-message limit for each size.
  """

  use Ash.Type.Enum, values: [:small, :medium, :large]
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "shared"]

  def max_message_length(:small), do: 80
  def max_message_length(:medium), do: 120
  def max_message_length(:large), do: 200

  def label(:small), do: ~t"Small"
  def label(:medium), do: ~t"Medium"
  def label(:large), do: ~t"Large"
  def label(value), do: to_string(value)
end
