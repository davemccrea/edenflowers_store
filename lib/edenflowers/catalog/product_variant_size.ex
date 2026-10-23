defmodule Edenflowers.Catalog.ProductVariantSize do
  @moduledoc """
  The named product sizes and the card-message limit for each size.
  """

  use Ash.Type.Enum, values: [:small, :medium, :large]

  def max_message_length(:small), do: 80
  def max_message_length(:medium), do: 120
  def max_message_length(:large), do: 200
end
