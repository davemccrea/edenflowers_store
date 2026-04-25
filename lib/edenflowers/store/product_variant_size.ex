defmodule Edenflowers.Store.ProductVariantSize do
  use Ash.Type.Enum, values: [:small, :medium, :large]

  def max_message_length(:small), do: 80
  def max_message_length(:medium), do: 120
  def max_message_length(:large), do: 200
end
