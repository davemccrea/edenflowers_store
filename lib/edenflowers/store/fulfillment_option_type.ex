defmodule Edenflowers.Store.FulfillmentOptionType do
  use Ash.Type.Enum, values: [:fixed, :dynamic]
end
